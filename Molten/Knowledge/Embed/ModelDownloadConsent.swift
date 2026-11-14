//
//  ModelDownloadConsent.swift
//  Molten
//
//  Molten 2.0 — K-E3. The embedding model downloads once per device; the
//  size is shown before download and a cellular-data confirmation appears
//  on iOS. Consent is remembered per device.
//

import Foundation
import Network

enum ModelDownloadConsent {
    /// Approximate on-disk size of multilingual-e5-small (fp32 safetensors
    /// + tokenizer), measured in the M1 spike.
    static let estimatedSizeMB = 480

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: "knowledgeModelDownloadConsent")
    }

    static func recordConsent() {
        UserDefaults.standard.set(true, forKey: "knowledgeModelDownloadConsent")
    }

    /// K-E3: on iOS, ask before downloading over cellular. Wi-Fi and macOS
    /// proceed without the cellular prompt (the size is still shown in the
    /// onboarding/confirmation UI).
    static func needsCellularConfirmation() async -> Bool {
        #if os(iOS)
        if hasConsented { return false }
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.usesInterfaceType(.cellular))
            }
            monitor.start(queue: DispatchQueue(label: "molten.cellular-check"))
        }
        #else
        return false
        #endif
    }

    enum ConsentError: Error { case cellularConfirmationRequired }

    /// Gate used by the processing flow before ensureModel.
    static func check() async throws {
        if await needsCellularConfirmation() {
            throw ConsentError.cellularConfirmationRequired
        }
    }
}
