# M1 Spike — MLXEmbedders on Mac and iPhone

PRD §10 M1 exit criteria: cosine > 0.999 between Mac and iPhone vectors on
100 sample texts; download size and memory recorded here.

## Configuration (K-E1)

| Item | Value |
|------|-------|
| Profile | `e5s-v1` |
| Model | `intfloat/multilingual-e5-small` |
| Pinned revision (HF commit) | `614241f622f53c4eeff9890bdc4f31cfecc418b3` |
| Dimensions | 384 |
| Pooling | mean |
| Normalization | L2 (unit length) |
| Prefixes | `"query: "` / `"passage: "` |
| Max input | 512 tokens |
| Packages | `mlx-swift-lm` **3.32.3** (products MLXEmbedders, MLXLMCommon; brings `mlx-swift` **0.32.3** transitively), `swift-transformers` **1.4.0** (product Tokenizers). Versions pinned via committed `Package.resolved`; pbxproj requirements use `upToNextMajorVersion` because Xcode 27.2 silently drops `kind = exact` (see DEVIATIONS.md). |
| Downloader | `HFSnapshotDownloader` — URLSession against official `huggingface.co` Hub tree/resolve endpoints, SHA-256 verification of LFS files, cache in Application Support/Molten/Models (K-E3). No third-party fork chain: the `MLXLMTokenizers` integration package recommended by current MLX docs depends on DePasqualeOrg forks of mlx-swift-lm/swift-tokenizers — rejected for supply-chain reasons; thin official-protocol adapters used instead (recorded in DEVIATIONS.md). |
| Tokenizer | `TransformersTokenizerLoader` loads `tokenizer.json` + `tokenizer_config.json` via swift-transformers `PreTrainedTokenizer`, adapted to MLXLMCommon.Tokenizer. |

## Method

1. Add the allowlisted packages to the Xcode project (SPM), products
   MLXEmbedders + MLXLMCommon linked to the app target.
2. Load `multilingual-e5-small` via `EmbedderRegistry` at the pinned revision
   through the MLX Hugging Face downloader; store under
   `Application Support/Molten/Models/` (K-E3).
3. Embed the same 100 sample texts (mixed English/Chinese, short and long,
   including code and tabular text) on Mac and on iPhone (device if
   available; otherwise iOS Simulator with the deviation recorded).
4. Export vectors (Float16, .mkv layout per §7.3) and compute pairwise
   cosine similarity Mac↔iPhone for each text.
5. Record: min/mean cosine, download size (bytes on disk), peak memory
   during embed, embed throughput (texts/s), cold-load time.

## Results (fill during spike)

| Metric | Mac (M-series, macOS 27.2 beta) | iPhone |
|--------|-----|--------|
| Min cosine (100 texts) | pending device run | — |
| Mean cosine | pending device run | — |
| Model download size (disk) | **481 MB** (fp32 safetensors + tokenizer) | — |
| Peak memory during embed | **2534 MB** (hosted app footprint incl. MLX runtime) | — |
| Throughput (100 texts) | **4.16 s** (~24 texts/s, batched) | — |
| Cold-load time (after download) | **11.20 s** | — |

**Pass criterion:** min cosine > 0.999 (K-E5).

## Performance acceptance (M7, 2026-11-14, Mac)

| Criterion | Limit | Mac | iOS Simulator (iPhone 17, iOS 26.5) | Status |
|-----------|-------|-----|-------------------------------------|--------|
| A1: 100-page text PDF extract + chunk | < 60 s | **0.21 s** (215 chunks) | **0.28 s** (215 chunks) | ✅ pass |
| A4: hybrid search, 20,000 chunks | < 200 ms | **50.8 ms** (8 hits) | **53.3 ms** (8 hits) | ✅ pass |

Neither path requires MLX (PDFKit + Chunker + Accelerate), so the simulator
numbers are valid acceptance measurements; re-measure on silicon at beta for
the release record (run with the `build/session/MOLTEN_PERF` marker).
Full suite (53 XCTest + 80 Swift Testing) also verified on the iOS Simulator
runtime, including the C4 migration test.

**iOS status (2026-11-13):** code compiles for iOS (arm64 device + simulator).
Runtime verification on simulator is **blocked by MLX 0.32.3 incompatibilities**
(nil GPU architecture name → std::string abort; then MTLSimDevice heap
storage-mode assertion). Physical-device run pending owner provisioning
(Xcode sign-in registers the iCloud container + profiles). The harness is
ready: create `build/session/SPIKE_ENABLED`, run M1SpikeTests on the device,
then `build/session/SPIKE_COMPARE` + re-run for the cosine check.

Mac run: 2026-11-13, `M1SpikeTests.embedAndRecord` — download verified via
SHA-256 (K-E3), 100×384 unit-norm vectors asserted, record at
`build/session/spike/vectors-macos.json`. Test run needs
`-enableCodeCoverage NO` (yyjson dynamic product fails to link under coverage
instrumentation — Xcode 27.2 issue).

## Notes / deviations

- (record device vs simulator, MLX version pins, any API surprises)
