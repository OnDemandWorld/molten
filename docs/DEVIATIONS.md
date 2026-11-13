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
| M2 | `EarlySupporterDetector.iosCutoffBuild` is `nil` in the M0 stub. Setting it requires the highest iOS `CFBundleVersion` shipped in 1.x from App Store Connect build history, which the coding agent cannot query. Highest known shipped build: **5** (v1.1, verified against the crash-report build version and project settings). | **Owner action before M2 merge:** confirm the 1.x build history in App Store Connect and set the cutoff; every 2.0 build number must be numerically greater. |
| PL4 | Turning off Apple Vision Pro availability in App Store Connect is a release-time owner action (tracked in §11 release plan). | No API access from the build environment. |
| §0.9 | Existing v1.1 tests are XCTest; new milestone tests use Swift Testing. Both frameworks coexist in the `MoltenTests` target. | PRD mandates Swift Testing for new tests; rewriting the existing suite is out of scope (§0.7: do not change existing behavior). |
| K-S1 (signing) | macOS compile + tests verified with `CODE_SIGNING_ALLOWED=NO`. The iCloud capability requires a Mac App Development provisioning profile; `xcodebuild -allowProvisioningUpdates` cannot authenticate the developer account from the agent environment ("login details rejected"). iOS Simulator builds succeed (no provisioning required). | **Owner action:** open the project in Xcode once, signed in as edward@ondemandworld.com, and let automatic signing register the iCloud container `iCloud.DVGF44TKAX.com.ondemandworld.molten` and create the profile. After that, normal signed builds work. Entitlements themselves are complete and identical across targets as required. |
