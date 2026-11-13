# Deviations from the Molten 2.0 PRD

Per PRD §0.8: when a requirement conflicts with platform or project reality,
the closest compliant behavior is implemented and recorded here with the
requirement ID and reason.

## M0 — Cleanup (2026-11-13)

| ID | Deviation | Reason |
|----|-----------|--------|
| PL2 | visionOS was already absent from `SUPPORTED_PLATFORMS` (`iphoneos iphonesimulator macosx`) and `TARGETED_DEVICE_FAMILY` (`1,2`). Removed the residual `CODE_SIGN_IDENTITY[sdk=xros*]` and `XROS_DEPLOYMENT_TARGET` build settings and all `#if os(visionOS)` code branches (15 files). | The v1.1 project never shipped a visionOS destination in build settings; only code branches and leftover settings existed. A15 verified via `xcodebuild -showdestinations`. |
| PL2 / K-S1 | The Share Extension target does not exist yet (created in M5). iCloud entitlements will be applied to it at creation, identical to the app's. | Cannot add entitlements to a target that does not exist. |
| K-S1 | The unit-test bundle has no entitlements file of its own; it is hosted in Molten.app (`TEST_HOST`) and inherits the host's entitlements at runtime. | Hosted test bundles are signed with the host app's identity; a separate entitlements file would have no effect. |
| K-S1 | Container identifier follows the PRD formula literally: `iCloud.DVGF44TKAX.com.ondemandworld.molten` (team prefix included, as written in §6.2 K-S1). | PRD §0.8: decisions are already made. The identifier must be registered in the Apple Developer portal; automatic signing with `-allowProvisioningUpdates` is used for development builds. |
| K-E1 | `EmbeddingProfile.e5sV1.modelRevision` is an empty placeholder in the M0 stub. | The commit-hash pin is established by the M1 spike (required before any embedding ships). |
| M2 | `EarlySupporterDetector.iosCutoffBuild` was `nil` in the M0 stub (fail-closed). **RESOLVED 2026-11-14:** owner confirmed highest shipped 1.x build = **6**; cutoff set to **7**; 2.0 ships as build 7. | — |
| PL4 | Turning off Apple Vision Pro availability in App Store Connect is a release-time owner action (tracked in §11 release plan). | No API access from the build environment. |
| §0.9 | Existing v1.1 tests are XCTest; new milestone tests use Swift Testing. Both frameworks coexist in the `MoltenTests` target. | PRD mandates Swift Testing for new tests; rewriting the existing suite is out of scope (§0.7: do not change existing behavior). |
| K-S1 (signing) | macOS compile + tests verified with `CODE_SIGNING_ALLOWED=NO`. The iCloud capability requires a Mac App Development provisioning profile; `xcodebuild -allowProvisioningUpdates` cannot authenticate the developer account from the agent environment ("login details rejected"). iOS Simulator builds succeed (no provisioning required). | **Owner action:** open the project in Xcode once, signed in as edward@ondemandworld.com, and let automatic signing register the iCloud container `iCloud.DVGF44TKAX.com.ondemandworld.molten` and create the profile. After that, normal signed builds work. Entitlements themselves are complete and identical across targets as required. |

## M6 — Conversations and context (2026-11-14)

| ID | Deviation | Reason |
|----|-----------|--------|
| C4/A10 | Migration test verifies the versioned plan reopens an existing store with zero data loss, 2.0-only fields nil on legacy rows, and search/export working on that data. A synthetic "drop the new columns" fixture proved unreliable in-process (SwiftData container caching + WAL semantics), so the physical v1.1→2.0 upgrade is verified by the PRD §11 beta step "upgrade a production 1.1 install to the beta" (owner action, M7). | v1.1→2.0 adds only optional properties — SwiftData lightweight migration; the plan is versioned for future custom stages. |
| X1 | Context ring estimates usage from the composer text; full-history usage accounting uses the X2 allocator at send time. Per-message historical usage display is a polish item. | Keeps the composer lightweight; the send-time budget is the functional guarantee. |

## M5 — Processing on the best device (2026-11-14)

| ID | Deviation | Reason |
|----|-----------|--------|
| K-U3 / K-S4 | **Implemented** (follow-up branch feature/m5-share-extension): MoltenShare app-extension target with base picker + new-base creation, writing directly into the shared iCloud container via the testable ShareImport helper; identical iCloud entitlements; embedded iOS-only (platformFilter). The earlier §10 cut is reversed. | Extension builds for iOS Simulator; on-device share-sheet verification is part of the owner device test pass. |
| A3 | Background continued processing implemented (BGContinuedProcessingTask, user-action triggered, per-file/per-stage durable outputs); the kill-and-resume acceptance run is a manual device test. | Requires a provisioned iPhone. |
| K-P3 | Two-device role behavior (Mac processes, iPhone shows Waiting for Mac) unit-tested at the logic level; live two-device script is a manual owner test. | Same provisioning constraint as M4. |

## M4 — Knowledge, iCloud (2026-11-14)

| ID | Deviation | Reason |
|----|-----------|--------|
| A2/A13 | Two-device acceptance (Mac→iPhone searchable ≤5 min with zero iPhone processing; same bases visible on all devices) implemented and unit-verified at the logic level (ingest-only watchers, profile gating, mapping stability); the live two-device run is a **manual owner test** — requires provisioned devices and a signed-in iCloud account. | Agent environment cannot provision devices or sign into iCloud. Test script: create a base on Mac, drop a PDF, wait for sync, open Molten on iPhone, verify the base appears and search returns cited passages without the iPhone extracting/embedding (check its Index cache only receives .mkt/.mkv). |
| K-S6 | Container debug check runs at launch; with no iCloud account signed in it logs the local-fallback path (expected in development). | Environment limitation, not a code deviation. |

## M3 — Knowledge, local (2026-11-13)

| ID | Deviation | Reason |
|----|-----------|--------|
| A1/A4 | Performance acceptance (100-page PDF <60s; 20k-chunk search <200ms on iPhone) measured on Mac only for now; iPhone numbers require the provisioned device run (same owner action as M1). | Device provisioning blocked in agent environment. |
| K-R5 | Citation chips open the source file; in-page passage highlighting not implemented yet ("where possible"). | PDFKit page navigation lands in M4 polish; opening the file satisfies the core flow. |
| K-U3 | Share Extension arrives in M5 per the milestone plan; Mac drag-into-folder works via Finder (the shared folder layout is the drop target). | Planned sequencing, not a cut. |
| X1 | Context window defaults (8192 server / 4096 AFM) used by K-R4 until M6 wires Ollama /api/show metadata and the composer ring. | X1/X2 formalized in M6; X2 allocator already implemented and used. |

## M2 — Entitlements (2026-11-13)

| ID | Deviation | Reason |
|----|-----------|--------|
| M2 | `EarlySupporterDetector.iosCutoffBuild` — **RESOLVED 2026-11-14: set to 7** (highest 1.x build = 6, owner-confirmed). ASC products created by owner. | — |
| M6 exit | The pure M6 matrix (version comparison, per-platform cutoffs, malformed/empty, sandbox/xcode, tier math incl. Early Supporter + subscription and lifetime, Keychain-only offline grant) all pass. The four SKTestSession flows (buy/lapse/lifetime/simulated-ES+subscription) are implemented but **gated behind `build/session/STOREKIT_FLOWS_ENABLED`**: SKTestSession requires a provisioned test host, and the iCloud entitlement cannot be provisioned from the agent environment (ad-hoc signing rejected: "requires a provisioning profile"). | **Owner action:** after the Xcode sign-in (same action as M0/M1), create the marker file and run M2EntitlementTests, or run them in Xcode with the Molten.storekit configuration (already set in the scheme's TestAction). |
| M7 | App Store Connect product creation (subscription group "Molten Membership", Plus level 2, 1-week trial, lifetime non-consumable; Pro level 1 reserved) is a portal action; `Molten.storekit` mirrors it for development. | **Owner action** at release prep (§11). |

## M1 — Embedding spike (2026-11-13)

| ID | Deviation | Reason |
|----|-----------|--------|
| §0.4 / K-E3 | Downloader is `HFSnapshotDownloader` (URLSession against official huggingface.co Hub tree/resolve endpoints, SHA-256 verification) instead of the `swift-huggingface` client package. | Keeps the spike dependency-free and fully auditable; official endpoints only (P1). M3 may swap in the official client without changing callers. |
| §0.4 | The MLX docs' recommended `MLXLMTokenizers` integration package (DePasqualeOrg/swift-tokenizers-mlx) was **rejected**: it depends on a fork chain (DePasqualeOrg/mlx-swift-lm, swift-tokenizers, swift-hf-api), not the official packages. Thin adapters over official `swift-transformers` 1.4.0 implement MLXLMCommon's `TokenizerLoader`/`Tokenizer` protocols instead. | Supply-chain safety; PRD allowlist intent is official packages. |
| K-E1 | Packages pinned exact: `mlx-swift-lm` 3.32.3 (MLXEmbedders + MLXLMCommon; mlx-swift 0.32.x transitive), `swift-transformers` 1.4.0. Model revision pinned: `614241f622f53c4eeff9890bdc4f31cfecc418b3`. | Reproducible builds (v1.1 convention). |
| M1 exit | Cross-device cosine: Mac run complete (numbers in SPIKE.md). iOS runtime verification **blocked on two fronts**: (1) physical-iPhone build needs provisioning — developer-account login rejected from the agent environment and the wildcard team profile lacks the iCloud capability/container; (2) iOS Simulator is incompatible with MLX 0.32.3 — nil GPU architecture name aborts std::string (worked around via MLX_METAL_GPU_ARCH), then MTLSimDevice asserts `MTLStorageModePrivate is required for heaps`. iOS code compiles for device + simulator. | Closest compliant behavior per §0.8: everything implemented, Mac verified, iOS compile-verified; K-E5 device measurement deferred. **Owner action:** open Xcode signed in once (registers iCloud container + profiles, unblocks M0 signing and device builds), then run M1SpikeTests on the physical iPhone (harness ready: build/session/SPIKE_ENABLED marker, then SPIKE_COMPARE for the cosine check). |
| tooling | **Root cause found:** Xcode 27.2 (27B52) `xcodebuild` silently ignores package requirements written as `kind = exact; version = …` — resolution skips them without any error (verified with fresh DerivedData, emptied Package.resolved, XML-validated pbxproj). Switching the requirement to `kind = upToNextMajorVersion; minimumVersion = …` (the format of the project's existing entries) resolves immediately. | Version pinning is preserved by the committed `Package.resolved` (mlx-swift-lm 3.32.3, swift-transformers 1.4.0, mlx-swift 0.32.3). Future package additions must use upToNextMajorVersion/Minor requirements, not `exact`, until this Xcode bug is fixed. |
| containment | Owner request (2026-11-13): all session-generated artifacts stay under the working directory — scripts/logs in `build/session/`, builds via `-derivedDataPath build/DerivedData`, package clones via `-clonedSourcePackagesDirPath build/SourcePackages` (all gitignored). | Harness memory files remain in `~/.claude/projects/…/memory/` by design. |
