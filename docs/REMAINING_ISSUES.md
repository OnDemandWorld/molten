# Molten 2.0 — Remaining issues & alternative solutions

Status at PRs #2–#11: all requirement IDs implemented; 53 XCTest + 80 Swift
Testing green on macOS; iOS Simulator builds (incl. MoltenShare.appex).
What remains falls into three buckets.

---

## Bucket 1 — Verifiable on the iOS Simulator (no MLX needed)

MLX 0.32.3 crashes on the simulator (two fatal assertions: nil GPU
architecture name in `device.cpp`, then `MTLSimDevice` heap storage-mode
assertion). **But most acceptance criteria never touch MLX:**

| Issue | Why it blocked | Alternative (no device needed) |
|-------|----------------|--------------------------------|
| A1: 100-page PDF < 60s | Assumed device-only | PDFKit + Chunker run on the simulator; the chunker falls back to the character estimator without the model. Run the gated perf suite on the simulator. |
| A4: 20k-chunk search < 200ms | Assumed device-only | Vector search is Accelerate/vDSP, not MLX; the test inserts synthetic vectors. Runs on the simulator. |
| C4/A10: v1.1 → 2.0 migration | Column-drop fixture unreliable in-process | Install the **shipped 1.1 build** on the simulator (1.1 has no MLX — runs fine), create conversations, then install 2.0 over it and verify. True upgrade path, no hardware. |
| A2/A13: two-device sync, zero receiving-side processing | Assumed two physical devices | The **receiving** side never runs MLX (ingest-only watchers + keyword/vDSP search). Sign the simulator into iCloud (Settings app inside the simulator) alongside the Mac; drop a file on the Mac, verify it becomes searchable in the simulator with no extraction/embedding there. |
| A3: kill/resume durability | Assumed device | Per-file/per-stage outputs are content-addressed; the in-process resume test covers the logic. Simulator background-task behavior can be exercised by swiping the app during a Process now run. |

**DONE (2026-11-14):** full suite verified on the iOS Simulator runtime
(iPhone 17, iOS 26.5): 53 XCTest + 80 Swift Testing pass, including the C4
migration test and the K-P4 iOS stage policy. A1/A4 measured on the
simulator: **A1 0.28s, A4 53.3ms** — both pass (see docs/SPIKE.md).
Simulator-class numbers; re-measure on silicon at beta for the release
record. Remaining in this bucket: the simulator+iCloud two-device pass
(A2/A13) and the 1.1→2.0 simulator upgrade (C4 physical path) — both need
an iCloud sign-in inside the simulator, an owner step.

## Bucket 2 — Needs a provisioned device (one Xcode sign-in unblocks)

| Issue | Why blocked | Alternative / mitigation |
|-------|-------------|--------------------------|
| K-E5/M1: embedding spike + cross-device cosine > 0.999 | MLX cannot run on the simulator; device builds need provisioning | (a) Owner signs into Xcode once → automatic provisioning → run the spike on the iPhone (markers ready). (b) Watch for an mlx-swift release fixing simulator support, then re-run on simulator. (c) Interim: verify the pipeline with Ollama embeddings — **not** K-E5-compliant (different engine), diagnostic only. |
| iPhone-class A1/A4 numbers | Same provisioning | Simulator numbers first (Bucket 1); device numbers at beta. |
| Share sheet on device | Extension needs a signed host | Simulator install can exercise the share sheet without provisioning (simulator builds are unsigned). |

**Automation alternative to interactive sign-in:** an App Store Connect API
key (`xcodebuild -authenticationKeyPath/-keyID/-issuerID`, or fastlane
match) provisions profiles non-interactively — useful for CI later; the
owner creates the key once in ASC ▸ Users ▸ Integrations.

## Bucket 3 — Owner/portal actions (no code alternative)

| Issue | Action |
|-------|--------|
| `iosCutoffBuild` | ASC ▸ build history: highest shipped 1.x iOS build; set the cutoff above it (2.0 builds start at 6). Fail-closed until set — no iOS Early Supporter grants. |
| ASC products | Create group "Molten Membership": Plus level 2 (monthly $2.99, yearly $19.99 + 1-week trial), lifetime $49.99; Pro level 1 reserved, not created. `Molten.storekit` mirrors this for development. |
| A8/A9 production upgrade | TestFlight: upgrade a real 1.1 install; thank-you sheet + Plus via Keychain on every device. The DEBUG simulate toggle covers development; production detection can't be simulated (M3 forbids it by design). |
| StoreKit live flows | SKTestSession flows are implemented and gated (`STOREKIT_FLOWS_ENABLED`); they need a signed host. Run in Xcode with the Molten.storekit configuration. |
| PL4 / pricing / release | ASC: Vision Pro availability off; price Free; manual release after approval; listing update (materials in docs/APP_STORE_v2.md). |

---

## Recommended sequence

1. **Now (agent-runnable):** full suite + A1/A4 on the simulator; record numbers.
2. **Owner, ~15 min:** Xcode sign-in (provisioning) + ASC build history check.
3. **Agent/owner:** device spike (K-E5), StoreKit flows, share sheet, two-device iCloud pass (or the simulator+iCloud alternative above).
4. **Owner:** TestFlight 1.1-upgrade (A8/A9), then release steps (M8).
