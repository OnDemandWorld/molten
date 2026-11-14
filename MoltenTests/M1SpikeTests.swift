//
//  M1SpikeTests.swift
//  MoltenTests
//
//  Molten 2.0 — M1 spike harness (PRD §10 M1, K-E5, docs/SPIKE.md).
//  Gated: runs only with MOLTEN_SPIKE=1 (downloads the ~118M model once).
//
//  Run on Mac:
//    MOLTEN_SPIKE=1 xcodebuild test -scheme Molten -destination 'platform=macOS' \
//      -only-testing:MoltenTests/M1SpikeTests
//  Run on iOS Simulator (same command, iOS destination), then compare:
//    MOLTEN_SPIKE=1 MOLTEN_SPIKE_COMPARE=1 xcodebuild test ... -only-testing:.../crossDeviceCosine
//
//  Vectors + metrics are written to /tmp/molten-spike/vectors-<platform>.json.
//

import Foundation
import MLX
import Testing
@testable import Molten

#if os(macOS)
private let platformTag = "macos"
#else
#if targetEnvironment(simulator)
private let platformTag = "ios-simulator"
#else
private let platformTag = "ios-device"
#endif
#endif

/// Repo root derived from the compiled source path (containment: all spike
/// artifacts live under build/session/, gitignored).
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let spikeDir: URL = {
    #if os(macOS) || targetEnvironment(simulator)
    return repoRoot.appendingPathComponent("build/session/spike", isDirectory: true)
    #else
    // On-device: write to the app's Documents (retrievable via devicectl).
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("molten-spike", isDirectory: true)
    #endif
}()

/// Gated by env var OR a marker file (xcodebuild's TEST_RUNNER_ env forwarding
/// proved unreliable for hosted unit tests; the marker is deterministic).
private var spikeEnabled: Bool {
    if ProcessInfo.processInfo.environment["MOLTEN_SPIKE"] == "1" { return true }
    return FileManager.default.fileExists(atPath:
        repoRoot.appendingPathComponent("build/session/SPIKE_ENABLED").path)
}
private var spikeCompareEnabled: Bool {
    if ProcessInfo.processInfo.environment["MOLTEN_SPIKE_COMPARE"] == "1" { return true }
    return FileManager.default.fileExists(atPath:
        repoRoot.appendingPathComponent("build/session/SPIKE_COMPARE").path)
}

/// 100 deterministic sample texts: English, Chinese, code, tabular, long form.
private let sampleTexts: [String] = {
    var texts: [String] = [
        "The lighthouse keeper found a door at the bottom of the sea.",
        "Elephants are the largest land animals on Earth.",
        "Photosynthesis converts light energy into chemical energy.",
        "The stock market closed higher on Friday despite inflation fears.",
        "A regular expression is a sequence of characters that specifies a search pattern.",
        " mitochondria are the powerhouse of the cell.",
        "The treaty was signed in 1648, ending the Thirty Years' War.",
        "Sourdough bread relies on wild yeast and lactobacilli.",
        "Quantum entanglement correlates particles across arbitrary distances.",
        "The café on the corner serves the best espresso in town.",
        "灯塔看守人在海底发现了一扇门。",
        "光合作用将光能转化为化学能。",
        "量子纠缠使粒子在任意距离上保持关联。",
        "街角的咖啡馆供应镇上最好的浓缩咖啡。",
        "机器学习模型需要大量数据进行训练。",
        "let array = [1, 2, 3].map { $0 * 2 }",
        "func greet(name: String) -> String { return \"Hello, \\(name)\" }",
        "SELECT name, COUNT(*) FROM users GROUP BY name HAVING COUNT(*) > 1;",
        "def fibonacci(n):\n    a, b = 0, 1\n    for _ in range(n):\n        a, b = b, a + b\n    return a",
        "git commit -m \"fix: resolve race condition in stream handler\"",
        "| Year | Revenue | Growth |\n| 2023 | 1.2M | 12% |\n| 2024 | 1.5M | 25% |",
        "Q3 results: revenue $1.5M (+25% YoY), margin 34%, headcount 42.",
        "The quick brown fox jumps over the lazy dog.",
        "Inflation erodes purchasing power over time.",
        "TCP guarantees ordered, reliable delivery of a byte stream.",
    ]
    // Deterministic long-form variants to reach 100 samples.
    let topics = ["tax law", "contract review", "marine biology", "compiler design", "medical research"]
    let langs = ["English", "中文", "日本語", "Español", "Deutsch"]
    var i = 0
    while texts.count < 100 {
        let topic = topics[i % topics.count]
        let lang = langs[(i / topics.count) % langs.count]
        texts.append("Document \(i + 1) about \(topic), written in \(lang). " +
                     String(repeating: "This section discusses practical implications and edge cases. ", count: 6))
        i += 1
    }
    return texts
}()

private func peakMemoryMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

private func directorySizeMB(_ url: URL) -> Double {
    guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let f as URL in en {
        total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    return Double(total) / 1_048_576
}

private struct SpikeRecord: Codable {
    let platform: String
    let modelRevision: String
    let texts: [String]
    let vectors: [[Float]]
    let embedSeconds: Double
    let peakMemoryMB: Double
    let modelSizeMB: Double
    let loadSeconds: Double
}

@Suite("M1 Spike — MLXEmbedders e5-small", .enabled(if: spikeEnabled))
struct M1SpikeTests {

    @Test("Embed 100 samples and record vectors + metrics")
    func embedAndRecord() async throws {
        #if targetEnvironment(simulator)
        // MLX 0.32.3 is incompatible with the iOS simulator (verified
        // 2026-11-13): (1) device.cpp builds std::string from a nil
        // architecture name — MLX_METAL_GPU_ARCH short-circuits that query;
        // (2) MTLSimDevice then asserts on heap storage modes. The spike
        // therefore runs on physical iOS devices only (see DEVIATIONS.md).
        // Kept for future MLX versions that fix simulator support.
        setenv("MLX_METAL_GPU_ARCH", "applegpu9", 1)
        MLX.Device.setDefault(device: MLX.Device(.cpu))
        #endif
        try FileManager.default.createDirectory(at: spikeDir, withIntermediateDirectories: true)
        let service = EmbeddingService.shared

        let loadStart = Date()
        try await service.ensureModel { fraction in
            if Int(fraction * 100) % 25 == 0 { print("model download: \(Int(fraction * 100))%") }
        }
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let embedStart = Date()
        let vectors = try await service.embed(passages: sampleTexts)
        let embedSeconds = Date().timeIntervalSince(embedStart)

        #expect(vectors.count == 100)
        #expect(vectors.allSatisfy { $0.count == 384 })
        // K-E1: unit-length vectors.
        for v in vectors {
            let norm = (v.reduce(0) { $0 + $1 * $1 }).squareRoot()
            #expect(abs(norm - 1.0) < 0.01)
        }

        let record = SpikeRecord(
            platform: platformTag,
            modelRevision: EmbeddingProfile.e5sV1.modelRevision,
            texts: sampleTexts,
            vectors: vectors,
            embedSeconds: embedSeconds,
            peakMemoryMB: peakMemoryMB(),
            modelSizeMB: directorySizeMB(HFSnapshotDownloader.modelsRoot),
            loadSeconds: loadSeconds
        )
        let out = spikeDir.appendingPathComponent("vectors-\(platformTag).json")
        try JSONEncoder().encode(record).write(to: out)
        print("M1 spike: wrote \(out.path) — embed \(String(format: "%.2f", embedSeconds))s, " +
              "load \(String(format: "%.2f", loadSeconds))s, mem \(String(format: "%.0f", record.peakMemoryMB))MB, " +
              "model \(String(format: "%.0f", record.modelSizeMB))MB")
    }

    @Test("K-E5: cross-device cosine > 0.999", .enabled(if: spikeCompareEnabled))
    func crossDeviceCosine() throws {
        let files = try FileManager.default.contentsOfDirectory(at: spikeDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("vectors-") }
        let records = try files.map { try JSONDecoder().decode(SpikeRecord.self, from: Data(contentsOf: $0)) }
        try #require(records.count >= 2, "Need vectors from at least two platforms; run the spike on Mac and iOS first")
        guard let a = records.first, let b = records.last else { return }
        #expect(a.modelRevision == b.modelRevision)
        #expect(a.texts == b.texts)
        #expect(a.vectors.count == b.vectors.count)

        var minCos: Float = 1.0
        var sum: Double = 0
        for (va, vb) in zip(a.vectors, b.vectors) {
            let dot = zip(va, vb).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            let na = (va.reduce(0) { $0 + $1 * $1 }).squareRoot()
            let nb = (vb.reduce(0) { $0 + $1 * $1 }).squareRoot()
            let cos = dot / (na * nb)
            minCos = min(minCos, cos)
            sum += Double(cos)
        }
        let mean = sum / Double(a.vectors.count)
        print("M1 spike cross-device: min cosine \(minCos), mean \(mean) (\(a.platform) vs \(b.platform))")
        #expect(minCos > 0.999, "K-E5 spike criterion: cosine above 0.999 for the same text across devices")
    }
}
