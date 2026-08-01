# Molten — Audit Remediation Status

**Review date:** 2026-08-01 · **Review mode:** read-only post-implementation verification · **Reviewer:** independent review pass (claims re-derived from current repo state, builds, and tests — not from commit messages)

---

## 1. Executive summary

- **Branch / HEAD:** `audit/ios-review` @ `ea846117e31f63697bbe5509fe811279cbc0683f` (`ea84611 test(F-17): add day-deletion regression coverage`). Note: the expected `fix/ios-audit-stabilization` branch does not exist; work continued on `audit/ios-review`, which the original instructions explicitly permitted. `main` remains untouched at the baseline.
- **Baseline:** `af7ba466e3a6affe6ad8c3e6b907b0d47cd80761` ("Release v1.0.1"), which is also `git merge-base HEAD main`.
- **Overall remediation status:** 6 linear commits since baseline implementing the approved stabilization tranche: F-01+F-43 (P0 data loss), F-02+F-18 (build reproducibility), F-05 (stream cancellation), F-10+F-11 (privacy manifest + local-network purpose string), F-12+F-59 (logging privacy), F-17 (test target + regression tests). 22 files changed (+536/−88), 3 files added.
- **Does the app build?** **Yes — fully.** macOS Debug, macOS Release, iOS Simulator Debug, and iOS Simulator Release all reach **BUILD SUCCEEDED** (complete builds, including asset catalogs), verified fresh during this review on Xcode 26.6.
- **Do tests actually run?** **Yes.** `MoltenTests` executes on both macOS and iOS Simulator (iPhone 17, iOS 26.5) destinations: **4/4 tests pass on each**, zero skipped.
- **Finding tallies (tranche scope):** 5 findings **VERIFIED COMPLETE** (F-01/F-43, F-02/F-18, F-10, F-12/F-59, F-17); 2 findings **IMPLEMENTED, MANUAL VERIFICATION REQUIRED** (F-05 live stop behavior; F-11 physical-device prompt). 0 partial, 0 regressed, 0 not implemented within scope. The remaining ~60 original audit findings are untouched backlog (§12).
- **Highest remaining risks:** (1) F-11 LAN behavior unverified on a physical iPhone — if the Local Network prompt is silently denied, core iOS functionality is broken for fresh installs (potentially P0); (2) no SwiftData schema versioning (F-03) — any future model change risks launch crash loops for existing users; (3) reachability timer death after backoff (F-06) and cross-actor SwiftData mutation (F-07) remain live correctness risks; (4) tokens still in plaintext UserDefaults (F-09).
- **Recommended next batch:** **Batch 1 — Small correctness** (F-20, F-25, F-26, F-42, F-44/F-48, O-02, plus the delete-error-path micro-fix found in this review). All XS/S, no persistence-schema or compliance changes, each independently testable.

---

## 2. Review scope and rules

- **Scope:** read-only verification of all changes since `af7ba46`; independent re-confirmation of each claimed fix via source inspection, fresh builds, fresh test runs, and built-product inspection; regression scan of the full diff; backlog re-ranking.
- **Rules honored:** no production source, tests, project, scheme, lockfile, plist, manifest, entitlement, asset, or build-setting modifications; no git mutations (no commit/push/branch-switch/reset); only this documentation file created; no formatters run.
- **Environment:** Apple Silicon Mac; Xcode 26.6 (build 17F113); SDKs iOS 26.5 / macOS 26.5; simulator runtimes iOS 18.2, 18.5, 26.0, 26.1, 26.2, 26.4, **26.5 (23F77)**; 83 available simulator devices; internet available (SPM resolution succeeded).
- **Environment change since implementation:** the iOS 26.5 simulator runtime was installed after the implementation session, making iOS Simulator destinations discoverable — this review therefore provides *stronger* evidence (iOS Simulator builds + tests) than the implementation session could (macOS-only tests, `-sdk`-only iOS builds).
- **Limitations:** builds were unsigned (`CODE_SIGNING_ALLOWED=NO`), so entitlements could not be inspected via `codesign` and no archive/Organizer privacy report was generated; no physical iOS device available; no App Store Connect access; F-05 cancellation verified structurally, not against a live model server.

---

## 3. Git and repository state

| Item | Value |
|---|---|
| Repository | `/Users/eplt/SCM/molten` (confirmed via `pwd`) |
| Current branch | `audit/ios-review` |
| HEAD | `ea846117e31f63697bbe5509fe811279cbc0683f` |
| `main` | `af7ba466e3a6affe6ad8c3e6b907b0d47cd80761` (local and `origin/main` identical; untouched) |
| Merge base (HEAD, main) | `af7ba466e3a6affe6ad8c3e6b907b0d47cd80761` (= baseline; history is linear, 6 commits ahead) |
| Working tree | **Clean of modifications.** Untracked only: `?? CLAUDE.md`, `?? IOS_TECHNICAL_AUDIT.md` (pre-existing documentation from the audit phase; preserved, never committed). No staged changes, no unstaged changes. |
| `git diff --check af7ba46..HEAD` | Clean (exit 0 — no whitespace errors) |

**Commits since af7ba46 (oldest → newest):**

```
20afb3e fix(F-01,F-43): restrict conversation deletion to selected day
ab22331 build(F-02,F-18): pin package resolution and fix KeyboardShortcuts API
631272e fix(F-05): cancel streaming producer tasks
3a307c6 privacy(F-10,F-11): add manifest and local-network purpose string
173a45d privacy(F-12,F-59): remove sensitive release logging
ea84611 test(F-17): add day-deletion regression coverage
```

**Changed-file summary (22 files, +536/−88):**

| Status | File | Tranche purpose |
|---|---|---|
| M | `.gitignore` | un-ignore + re-include the SPM lockfile (F-18) |
| M | `Molten.xcodeproj/project.pbxproj` | package requirement pins (F-02/F-18); PrivacyInfo.xcprivacy resource wiring (F-10); INFOPLIST_KEY_NSLocalNetworkUsageDescription (F-11); MoltenTests target (F-17) |
| A | `Molten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | committed lockfile (F-18) |
| M | `Molten.xcodeproj/xcshareddata/xcschemes/Molten.xcscheme` | TestAction → MoltenTests testable (F-17) |
| M | `Molten/Application/MoltenApp.swift` | `onGlobalKeyboardShortcut` → `onKeyboardShortcut` (F-02) |
| M | `Molten/Helpers/Accessibility.swift` | remove selected-text logging (F-12) |
| A | `Molten/PrivacyInfo.xcprivacy` | app privacy manifest (F-10) |
| M | `Molten/Services/AppleFoundationService.swift` | producer cancellation (F-05) |
| M | `Molten/Services/SpeechService.swift` | logging → os.Logger (F-12) |
| M | `Molten/Services/SwamaService.swift` | producer cancellation (F-05) + payload-log removal / os.Logger (F-12) |
| M | `Molten/Services/SwiftDataService.swift` | day-ranged delete predicate (F-01/F-43) + `init(inMemory:)` test seam (F-17) |
| M | `Molten/Stores/ConversationStore.swift` | selection-preserving async day delete (F-01) |
| M | `Molten/Stores/LanguageModelStore.swift` | logging → os.Logger (F-12) |
| M | `Molten/UI/Shared/ApplicationEntry.swift` | logging → os.Logger (F-12) |
| M | `Molten/UI/Shared/Chat/Chat.swift` | async day-delete call-site wrappers (F-01) |
| M | `Molten/UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift` | remove debug/profane prints (F-59) |
| M | `Molten/UI/iOS/ChatView_iOS.swift` | remove bare "Failed" print (F-12) |
| M | `Molten/UI/macOS/Chat/Components/InputFields_macOS.swift` | logging → os.Logger (F-12) |
| M | `Molten/UI/macOS/PromptPanel/FloatingPanel.swift` | remove debug prints (F-59) |
| M | `Molten/UI/macOS/PromptPanel/PanelCompletionsVM.swift` | remove prompt/response logging; error → os.Logger (F-12) |
| M | `Molten/UI/macOS/PromptPanel/PanelManager.swift` | remove "Animation completed" print (F-59) |
| A | `MoltenTests/DayDeletionTests.swift` | day-deletion regression suite (F-17) |

**Committed vs uncommitted:** every remediation change is committed; the only uncommitted items are the two pre-existing untracked audit documents.

---

## 4. What was built (per commit)

### 20afb3e — fix(F-01,F-43): restrict conversation deletion to selected day
- **Files:** `SwiftDataService.swift`, `ConversationStore.swift`, `Chat.swift`.
- **Behavior changed:** the per-day context-menu action no longer deletes all conversations. `SwiftDataService.deleteConversations(_:calendar:)` deletes rows whose `updatedAt` falls in `[startOfDay, startOfNextDay)` and calls `saveChanges()`; `ConversationStore.deleteDailyConversations(_:)` became `@MainActor async`, reloads history, and clears the open conversation only when it belonged to the deleted day. Call sites wrap the async method in `Task`.
- **Audit IDs:** F-01 (P0), F-43.
- **Verification:** source inspection of the full call chain (§5A); 4 regression tests pass on macOS + iOS Simulator.
- **Scope deviation:** none.

### ab22331 — build(F-02,F-18): pin package resolution and fix KeyboardShortcuts API
- **Files:** `project.pbxproj`, `MoltenApp.swift`, `.gitignore`, `Package.resolved` (added).
- **Behavior changed:** macOS entry point uses `onKeyboardShortcut(_:type:perform:)` (the API KeyboardShortcuts 2.0.1 actually exposes); Magnet/OllamaKit/Splash requirements changed from `kind = branch` to `kind = revision` at the exact audited SHAs; KeyboardShortcuts pinned `exactVersion 2.0.1`; lockfile tracked.
- **Audit IDs:** F-02 (macOS build broken at baseline), F-18 (unreproducible builds).
- **Verification:** clean `xcodebuild -resolvePackageDependencies` (exit 0; 14 pins; 0 branch pins; all revisions match the audited set — §6); macOS Debug+Release BUILD SUCCEEDED; no package contents upgraded (§6).
- **Scope deviation:** none.

### 631272e — fix(F-05): cancel streaming producer tasks
- **Files:** `SwamaService.swift`, `AppleFoundationService.swift`.
- **Behavior changed:** both `chatStream` producers retain their `Task` and register `continuation.onTermination = { @Sendable _ in task.cancel() }`, so consumer cancellation (Stop button, navigation, new prompt) stops network/model work — mirroring the pre-existing OllamaService pattern.
- **Audit IDs:** F-05.
- **Verification:** structural source verification (§5C); **no automated test possible without DI the tranche forbade** — live stop behavior remains manual-verification-required.
- **Scope deviation:** none.

### 3a307c6 — privacy(F-10,F-11): add manifest and local-network purpose string
- **Files:** `Molten/PrivacyInfo.xcprivacy` (added), `project.pbxproj`.
- **Behavior changed:** app now ships a privacy manifest (tracking=false; UserDefaults API category with CA92.1) and iOS builds declare `NSLocalNetworkUsageDescription`. No other Info.plist/entitlement/ATS change.
- **Audit IDs:** F-10, F-11.
- **Verification:** `plutil -lint` OK; manifest present exactly once at app level in iOS and macOS built products with correct contents (§10); generated iOS `Info.plist` contains the usage description (§5E); `NSAllowsArbitraryLoads` unchanged (ATS deliberately untouched).
- **Scope deviation:** none.

### 173a45d — privacy(F-12,F-59): remove sensitive release logging
- **Files:** 11 Swift files.
- **Behavior changed:** removed all prompt/response/body/selected-text logging and profane debug strings; retained non-sensitive error diagnostics converted to `os.Logger` (subsystem `com.ondemandworld.molten`, dynamic content `privacy: .private`).
- **Audit IDs:** F-12, F-59.
- **Verification:** exhaustive logging search (§5F) — zero active `print/debugPrint/dump/NSLog` in compiled sources; every remaining statement classified safe.
- **Scope deviation:** none. Dead helper files (`SleepTest`, `DeallocPrinter`), non-compiled legacy files (`EnchantedApp` etc.), and commented-out blocks were intentionally left untouched (dead-code cleanup is a separate approved batch).

### ea84611 — test(F-17): add day-deletion regression coverage
- **Files:** `project.pbxproj`, `Molten.xcscheme`, `SwiftDataService.swift`, `MoltenTests/DayDeletionTests.swift` (added).
- **Behavior changed:** new hosted `MoltenTests` unit-test target wired into the shared scheme; 4 regression tests for day deletion. Only production seam: `SwiftDataService.init(inMemory:)` defaulting to `false` (shared singleton unchanged).
- **Audit IDs:** F-17 (also regression coverage for F-01/F-43).
- **Verification:** `xcodebuild test` runs 4/4 green on macOS and iOS Simulator destinations (§8).
- **Scope deviation:** minor cosmetic whitespace trims inside the `SwiftDataService.init` block being legitimately modified — no behavioral effect.

---

## 5. Finding-by-finding status

| ID | Finding | Status | Evidence | Tests | Remaining work |
|---|---|---|---|---|---|
| F-01 + F-43 | Per-day deletion deleted everything; broken date predicate | **VERIFIED COMPLETE** | Call chain inspected end-to-end (§5A); half-open `[startOfDay, startOfNextDay)` on `updatedAt`; explicit `saveChanges()`; selection cleared only if in deleted day | 4/4 pass ×2 destinations | Error-path polish (§11); DST test coverage |
| F-02 + F-18 | macOS build broken; unreproducible resolution | **VERIFIED COMPLETE** | `onKeyboardShortcut` used; lockfile tracked/un-ignored; 3 forks revision-pinned; KeyboardShortcuts exactVersion 2.0.1; clean resolve stable; macOS Debug+Release succeed (§6) | n/a (build-level) | CI resolution gate (F-51, backlog) |
| F-05 | Stop doesn't stop Swama/Apple streams | **IMPLEMENTED, MANUAL VERIFICATION REQUIRED** | `onTermination → task.cancel()` in both services; finish paths mutually exclusive; post-termination finishes are no-ops (§5C) | none (DI unavailable in tranche) | Live stop verification vs Swama + Apple servers; automated test once a provider seam exists |
| F-10 | Missing app privacy manifest | **VERIFIED COMPLETE** | `plutil -lint` OK; present once at app level in iOS + macOS products; tracking=false, no domains, UserDefaults/CA92.1 (§10) | n/a | Archive Organizer privacy report (manual) |
| F-11 | Missing NSLocalNetworkUsageDescription | **IMPLEMENTED, MANUAL VERIFICATION REQUIRED** | Key + correct wording in generated iOS Info.plist; no Bonjour keys; ATS unchanged (§5E) | n/a | Physical-iPhone fresh-install prompt + LAN connection test |
| F-12 + F-59 | Sensitive/inappropriate release logging | **VERIFIED COMPLETE** (source-level) | 0 active print/debugPrint/dump/NSLog in compiled sources; all remaining logging is os.Logger with `.private` dynamic content; no sensitive patterns anywhere (§5F) | n/a | Runtime unified-log spot check optional |
| F-17 | No test target | **VERIFIED COMPLETE** | Real unit-test target; scheme Testable `skipped=NO`; 4/4 executed (nonzero, none skipped) on macOS + iOS Simulator; tests exercise production APIs (§8) | the tests themselves | Broader §13 starter suite (backlog) |

### 5A. F-01 + F-43 — detailed

**Call chain (current source):**
1. `ConversationHistoryListView` day-header context menu → `onDeleteDailyConversations(conversationGroup.date)`, where the group key is `Calendar.current.startOfDay(for: conversation.updatedAt)` (line 33).
2. `Chat.swift` (lines 144, 155) wraps the async store method: `{ date in Task { await conversationStore.deleteDailyConversations(date) } }`.
3. `ConversationStore.deleteDailyConversations(_:)` (`@MainActor`, async): computes `deletesSelectedConversation` via `Calendar.current.isDate(selected.updatedAt, inSameDayAs: date)`; `try? await swiftDataService.deleteConversations(date)`; `try? await loadConversations()`; clears `selectedConversation`/`messages` **only** if `deletesSelectedConversation`.
4. `SwiftDataService.deleteConversations(_ date: Date, calendar: Calendar = .current)`: `startOfDay = calendar.startOfDay(for: date)`; `startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)`; predicate `updatedAt >= startOfDay && updatedAt < startOfNextDay`; `modelContext.delete(model:where:)` + explicit `saveChanges()`.

**Checklist:** date argument used ✓ · half-open interval ✓ · startOfDay inclusive (`>=`) ✓ · next-day start exclusive (`<`) ✓ · same Calendar/time-zone interpretation as the UI (`Calendar.current` on all three participants) ✓ · only the target day deleted (tests) ✓ · saved explicitly ✓ · history reloaded (`loadConversations()`) ✓ · selection cleared only when deleted ✓.

**Predicate compatibility:** `#Predicate` captures two precomputed `Date` locals — supported by SwiftData; compiles and executes (tests pass against a real `ModelContainer`, in-memory).

**DST analysis:** `date(byAdding: .day, value: 1, to:)` is calendar arithmetic (not +86400 s), so on 23/25-hour transition days it yields the next midnight and the interval still covers exactly one calendar day. Correct by construction — but **no test exercises a DST-transitioning time zone** (test calendars are Pacific/Kiritimati/UTC+14 — no DST — and GMT). Missing coverage, low risk (§11).

**Tests:** see §8 — boundary cases (prev-day 23:59:59, exact midnight, noon, 23:59:59, next-day 00:00:00), non-UTC calendar, persistence proof, selection preservation and clearing.

### 5B. F-02 + F-18 — detailed

- `Package.resolved` tracked: `git diff --name-status af7ba46..HEAD` shows `A Molten.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Not ignored: `.gitignore` no longer lists `Package.resolved`; `*.xcworkspace/` is followed by a negation chain re-including the shared swiftpm dir and lockfile; `git check-ignore` confirms not ignored.
- Forks immutable: Magnet `4865f86d9baa…`, OllamaKit `0079411b4568…`, Splash `c31eba086610…` — all `kind = revision` in pbxproj, all equal to the audited resolution (no content change).
- KeyboardShortcuts: `kind = exactVersion; version = 2.0.1` → revision `2e5f15581fef…`.
- Entry point: `MoltenApp.swift` line 39 uses `.onKeyboardShortcut(KeyboardShortcuts.Name.togglePanelMode, type: .keyDown)` — verified against KeyboardShortcuts 2.0.1's `ViewModifiers.swift` (`onKeyboardShortcut(_:type:perform:)`, same signature as the old call).
- Clean resolution: `xcodebuild -resolvePackageDependencies` exit 0; lockfile unchanged after resolution; 14 pins, **0 branch pins**. Full pin table in §6.
- Builds: macOS Debug + Release both **BUILD SUCCEEDED** (§9) — the baseline's `onGlobalKeyboardShortcut` compile error is gone.
- No unrelated upgrades: every version pin equals the audited set (verified pin-by-pin).

### 5C. F-05 — detailed

- `SwamaService.chatStream`: `let task = Task { … }`; `continuation.onTermination = { @Sendable _ in task.cancel() }` (lines ~254-256). Cancellation reaches the network: `URLSession.shared.bytes(for:)` honors task cancellation (underlying request cancelled; iteration throws), and the in-loop `Task.isCancelled` check (lines ~188-189) exits with `continuation.finish(); return`.
- `AppleFoundationService.chatStream`: same handle + `onTermination` pattern (lines ~162-164); the in-loop `Task.isCancelled` check (lines ~112-113) stops chunk emission; structured cancellation propagates into the awaited `session.respond(to:)`.
- **Double-finish analysis:** Swama finish sites (invalid response, HTTP error, [DONE], cancel-check, natural end, catch) are mutually exclusive via `return`; Apple sites likewise. When the consumer has already terminated, `onTermination` fires and any later producer `finish(...)` is a documented no-op on `AsyncStream.Continuation` — no observable double completion.
- **Retain cycles:** transient `onTermination → task → continuation storage → onTermination` reference chain breaks at stream termination; identical shape to the pre-existing, accepted OllamaService `CancellableHolder` pattern.
- **Cancellation vs provider failure:** distinct — user cancellation exits via the `Task.isCancelled` branch (clean `finish()`), while transport/HTTP errors propagate via `finish(throwing:)`.
- **No automated test** (providers are network-bound singletons; DI was out of tranche scope). Manual/integration verification documented in the commit message and §16.

### 5D. F-10 — detailed

- `Molten/PrivacyInfo.xcprivacy`: `plutil -lint` → OK. Declares `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`, and exactly one accessed-API entry: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. Does not copy Alamofire's or any dependency's declarations.
- Target membership: pbxproj has exactly 4 references (build file, file reference, Molten group child, Resources phase entry) — included once.
- Built products (§10): exactly one app-level `PrivacyInfo.xcprivacy` per product (iOS root; macOS `Contents/Resources`); the additional manifests found are Alamofire's own, inside `Alamofire_Alamofire.bundle` (dependency's responsibility; also appears inside the hosted test bundle — benign).
- CA92.1 fit: all UserDefaults usage is `UserDefaults.standard`/`@AppStorage` (app's own defaults; no suites); no other required-reason categories detected in the audit (no file-timestamp/disk-space/boot-time APIs).

### 5E. F-11 — detailed

- Built iOS `Info.plist` contains `NSLocalNetworkUsageDescription` = "Molten connects to your local AI server, such as Ollama or Swama, on your network." — wording accurately describes the behavior.
- Applied via `INFOPLIST_KEY_NSLocalNetworkUsageDescription` in both Debug/Release target settings (same pattern as the mic/speech keys); generated into the iOS product. macOS product also carries it (harmless; macOS has no Local Network prompt).
- No `NSBonjourServices` entry ("Entry … Does Not Exist") — correct, the app does not browse/advertise.
- ATS untouched: `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` remains (F-28 deliberately out of tranche); `Molten/Info.plist` diff since baseline is empty.
- **Not physically verified:** prompt appearance and LAN connection success on a fresh-install iPhone require a device (§16).

### 5F. F-12 + F-59 — detailed

Exhaustive search of compiled sources (excluding proven non-compiled files `EnchantedApp.swift`, `Header.swift`, `Sidebar_macOS.swift`, `NSClipboardItem.swift` and dead helpers `SleepTest.swift`, `DeallocPrinter.swift`):

| Remaining statement | Classification |
|---|---|
| `SwamaService` logger: "invalid HTTP response" (static), "HTTP error status: \(statusCode)" (Int), "SSE buffer exceeded 1MB limit" (static), decode/stream errors (`localizedDescription, privacy: .private`) | safe production diagnostic |
| `ApplicationEntry` logger ×2, `LanguageModelStore` logger ×3, `SpeechService` logger ×2, `InputFields_macOS` logger, `PanelCompletionsVM.handleError` logger — all `error.localizedDescription, privacy: .private` | safe production diagnostic |
| `ChatMessageView.swift:197` — `print(5+5)` inside a Markdown code-sample string in `#Preview` | not a logging call (content literal) |

- Zero active `print(/debugPrint(/dump(/NSLog` in compiled sources. Zero DEBUG-only diagnostics remain (none were added). Zero matches for sensitive patterns (request body, base64, Authorization, apikey/bearertoken near any log call). The audit's profane strings ("denicd", "wtf", "heya"*) are gone from compiled code (*"heya" survives only in the non-compiled `EnchantedApp.swift`, intentionally untouched).
- No statement logs prompts, responses, history, selected text, speech content, image/base64 data, tokens, or headers.
- Unreachable/excluded sources with prints (dead helpers, non-compiled legacy, commented blocks) were left as-is per tranche constraints — deferred to dead-code cleanup (F-56 backlog).

### 5G. F-17 — detailed

- Real target: `MoltenTests` `PBXNativeTarget` with `productType = "com.apple.product-type.bundle.unit-test"`; `TEST_HOST`/`BUNDLE_LOADER` set in both configs; target dependency on `Molten`; appears in `xcodebuild -list` (Targets: Molten, MoltenTests).
- Scheme: `TestAction` contains a `TestableReference` with `skipped = "NO"` for `MoltenTests.xctest`.
- Test file membership: `DayDeletionTests.swift` appears in exactly one Sources build phase (the test target's) — no leakage into the app target.
- Production exercise: tests call production `SwiftDataService.deleteConversations(_:calendar:)`, `ConversationStore.deleteDailyConversations(_:)`, `createConversation`, `fetchConversations` against an in-memory `ModelContainer` (via the `inMemory:` seam) — the predicate is **not** reimplemented in test code.
- Runs: nonzero executed counts on two destinations, zero skipped (§8).

---

## 6. Dependency and reproducibility status

**Lockfile:** tracked, un-ignored, and honored — clean `xcodebuild -resolvePackageDependencies` exits 0 and leaves the committed file byte-identical (14 pins, 0 branch pins).

| Identity | Kind | Version / revision | Immutable? | Changed vs audited? |
|---|---|---|---|---|
| activityindicatorview | remoteSourceControl | 1.1.1 @ `9970fd0bb7a0` | yes (lockfile) | no |
| alamofire (transitive) | remoteSourceControl | 5.9.1 @ `f455c2975872` | yes (lockfile) | no |
| keyboardshortcuts | remoteSourceControl | **exactVersion 2.0.1** @ `2e5f15581fef` | **yes (requirement)** | requirement hardened (was upToNextMajor 2.0.0); same resolved revision |
| magnet (fork) | remoteSourceControl | **revision `4865f86d9baa24684dedacd6677beb2d8b30d88e`** | **yes (requirement)** | requirement hardened (was branch master); same revision |
| networkimage (transitive) | remoteSourceControl | 6.0.1 @ `2849f5323265` | yes (lockfile) | no |
| ollamakit (fork) | remoteSourceControl | **revision `0079411b4568dbc821c9e2589345d3f9b9538af4`** | **yes (requirement)** | requirement hardened (was branch main); same revision |
| sauce (transitive) | remoteSourceControl | 2.4.1 @ `df657bc1beba` | yes (lockfile) | no |
| splash (fork) | remoteSourceControl | **revision `c31eba0866102be9be29391dac641ecb46795702`** | **yes (requirement)** | requirement hardened (was branch master); same revision |
| swift-async-algorithms | remoteSourceControl | 1.0.0 @ `da4e36f86544` | yes (lockfile) | no |
| swift-cmark (transitive) | remoteSourceControl | 0.5.0 @ `3ccff77b2dc5` | yes (lockfile) | no |
| swift-collections (transitive) | remoteSourceControl | 1.1.0 @ `94cf62b3ba8d` | yes (lockfile) | no |
| swift-markdown-ui | remoteSourceControl | 2.4.1 @ `5f6133581482` | yes (lockfile) | no |
| vortex | remoteSourceControl | 1.0.1 @ `bb48b128d3c1` | yes (lockfile) | no |
| wrappinghstack | remoteSourceControl | 0.2.0 @ `3300f68b6bf5` | yes (lockfile) | no |

**Nothing is still floating:** the four previously floating packages (three forks + KeyboardShortcuts) now have immutable requirement-level pins; the remaining ten are version-requirement + lockfile-pinned. No package contents changed versus the audited resolution (reproducibility criterion = stable identities and immutable revisions — not byte-identical signed binaries). Audit-research note still valid: MarkdownUI is in maintenance mode upstream (future-modernization item, not actionable in this tranche).

---

## 7. Privacy and App Store status

- **Privacy manifest:** shipped in-app (iOS + macOS products), contents verified (§5D/§10). *Still requires:* archive → Organizer privacy report (manual).
- **Required-reason APIs:** UserDefaults/CA92.1 declared; no other categories in use per audit inspection.
- **Local-network usage description:** present in iOS generated Info.plist with accurate wording; *still requires:* physical-iPhone verification of prompt + connection (§16).
- **Logging privacy:** no sensitive content reachable from any active logging call (§5F). Unified-log runtime spot check optional.
- **ATS:** unchanged (`NSAllowsArbitraryLoads = true`) — F-28 remains backlog; the tranche was explicitly prohibited from narrowing it.
- **Items still requiring App Store Connect / physical-device / compliance verification:**
  1. Physical-iPhone fresh-install Local Network prompt + LAN connectivity (F-11).
  2. Archive privacy report rendering (F-10 confirmation at submission level).
  3. App Store Connect privacy labels vs the speech-recognition network path (F-30 — unaddressed; if on-device recognition isn't forced, labels/policy must disclose Apple processing).
  4. Export-compliance determination before adding `ITSAppUsesNonExemptEncryption` (F-50 — compliance sign-off required first).
  5. Distribution certificates/profiles state (unchanged by this tranche; not inspectable here).

---

## 8. Test inventory

All in `MoltenTests/DayDeletionTests.swift`; all executed (none skipped), passing on **both** `platform=macOS` and `platform=iOS Simulator,name=iPhone 17,OS=26.5`:

| Test | Production behavior exercised | Result |
|---|---|---|
| `testDeleteConversationsRemovesOnlyTargetCalendarDay` | `SwiftDataService.deleteConversations(_:calendar:)` with a fixed non-UTC calendar (Pacific/Kiritimati, UTC+14): rows at prev-day 23:59:59, midnight, noon, 23:59:59, next-day 00:00:00 → exactly the three in-day rows deleted | pass (both destinations) |
| `testDeleteConversationsIsPersisted` | explicit-save behavior: a fresh `ModelContext` over the same container (autosave off) sees only the survivor — proves `saveChanges()` | pass |
| `testStoreDeleteDailyKeepsOtherDaysAndUnrelatedSelection` | `ConversationStore.deleteDailyConversations(_:)` end-to-end with `Calendar.current`: other days survive; selection outside the deleted day preserved | pass |
| `testStoreDeleteDailyClearsSelectionWhenSelectedConversationDeleted` | selection + message clearing when the open conversation is inside the deleted day | pass |

**Important missing cases (recommended additions, not blockers):**
- DST-transition day in a transitioning time zone (e.g., America/Los_Angeles spring-forward/fall-back) — correctness is by Calendar arithmetic, but unproven by tests.
- Service-level error path: delete throws → selection should not be cleared (documents/fixes the §11 risk).
- Empty-store and no-match deletes (idempotence).

---

## 9. Build verification matrix

All commands run fresh during this review, from `/Users/eplt/SCM/molten`, Xcode 26.6 (17F113). Environment inventory first: `xcodebuild -version`, `-showsdks` (iOS 26.5 + macOS 26.5 SDKs), `xcrun simctl list runtimes` (iOS 18.2–26.5), `xcrun simctl list devices available` (83 devices), `-showdestinations` (macOS + iOS Simulator destinations; note: "iPhone 16" is not paired with the 26.5 runtime — "iPhone 17" is).

| # | Command (abridged) | Destination | Config | Result | Tests | Warnings | Complete? | Failure class |
|---|---|---|---|---|---|---|---|---|
| 0 | `xcodebuild -resolvePackageDependencies -project Molten.xcodeproj -scheme Molten` | — | — | **exit 0**, 0 errors | — | — | yes | — |
| 1 | `xcodebuild build … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | macOS (My Mac) | Debug | **BUILD SUCCEEDED** (exit 0) | — | 0 unique (warm incremental cache — no re-diagnostics) | yes, complete build | — |
| 2 | same | macOS | Release | **BUILD SUCCEEDED** (exit 0) | — | 50 unique, **all pre-existing** (0 on remediation lines) | yes | — |
| 3 | `xcodebuild build … -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' CODE_SIGNING_ALLOWED=NO` | iOS Simulator iPhone 17 / 26.5 | Debug | **BUILD SUCCEEDED** (exit 0) | — | pre-existing set | yes, incl. asset catalog | — |
| 4 | same | iOS Simulator iPhone 17 / 26.5 | Release | **BUILD SUCCEEDED** (exit 0) | — | pre-existing set | yes | — |
| 5 | `xcodebuild test … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | macOS | Debug | **TEST SUCCEEDED** (exit 0) | **4 executed, 0 failures, 0 skipped** | — | yes | — |
| 6 | `xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` | iOS Simulator | Debug | **TEST SUCCEEDED** (exit 0) | **4 executed, 0 failures, 0 skipped** | — | yes | — |
| 7 | `git diff --check af7ba46..HEAD` (re-run post-builds) | — | — | clean (exit 0) | — | — | — | — |

**Notes:**
- One failed attempt recorded transparently: `iPhone 16, OS=26.5` destination does not exist (that device isn't paired with the 26.5 runtime) — destination error, environmental, resolved by using `iPhone 17, OS=26.5`.
- Warning intersection: 50 unique warning locations across the four builds; **0 lie on lines added by the remediation** (verified programmatically against the `af7ba46..HEAD` added-line set). All are pre-existing strict-concurrency/deprecation warnings documented in the original audit (O-10 debt).
- The macOS Debug "0 warnings" is an incremental-cache artifact (no files recompiled); the Release and iOS builds show the true pre-existing set.
- The iOS 26.5 simulator runtime was installed after the implementation session; the implementation session's iOS verification used `-sdk` builds (also BUILD SUCCEEDED then) and macOS-only tests.

---

## 10. Build-product inspection

From the actual built products (`DerivedData/…/Build/Products`):

| Check | iOS Simulator Debug (`Molten.app`) | macOS Debug (`Molten.app`) |
|---|---|---|
| `CFBundleIdentifier` | `com.ondemandworld.molten` ✓ | `com.ondemandworld.molten` ✓ |
| `CFBundleShortVersionString` | `1.0.1` ✓ | `1.0.1` ✓ |
| `CFBundleVersion` | `4` ✓ | `4` ✓ |
| App-level `PrivacyInfo.xcprivacy` | present at app root; contents: tracking=false, no domains, UserDefaults/CA92.1 ✓ | present in `Contents/Resources`; same contents ✓ |
| Duplicate app manifests | none (other PrivacyInfo files are Alamofire's dependency bundle, incl. inside `PlugIns/MoltenTests.xctest` — benign) ✓ | none ✓ |
| `NSLocalNetworkUsageDescription` | present, correct wording ✓ | present (harmless on macOS) |
| Mic / speech usage descriptions | intact ✓ | intact |
| `NSBonjourServices` | absent ✓ | — |
| ATS | `NSAllowsArbitraryLoads = true` — unchanged from baseline (F-28 backlog) | unchanged |
| `PlugIns/MoltenTests.xctest` | present (hosted test bundle builds) ✓ | present ✓ |
| Entitlements | not inspectable without signing (`CODE_SIGNING_ALLOWED=NO`); source entitlement files unchanged since baseline (diff empty) | same |

---

## 11. Regressions and unresolved risks

**Confirmed regressions:** none found. Full-diff review covered: accidental data deletion outside the selected day (impossible per predicate + tests), SwiftData predicate compatibility (executes in tests), package requirement syntax (resolves cleanly), API mismatches (builds), test code leaking into production (single-phase membership), double completion (no-op semantics; exclusive paths), duplicate resources (single manifest), malformed manifest keys (plutil OK), local-network description platform scope (harmless on macOS), remaining sensitive logs (none), newly introduced warnings (0 on changed lines).

**Partial fixes:** none within tranche scope.

**Risks requiring follow-up (not confirmed defects):**
1. **Day-delete error path:** `ConversationStore.deleteDailyConversations` uses `try?` on the service delete; if the delete throws but the selection was in the target day, the selection is still cleared (deletion didn't happen). Pre-tranche behavior was worse (unconditional clear + delete-all), so this is residual imperfection, not a regression. Recommend surfacing the error (fits Batch 1's F-20 error-handling theme) + a test.
2. **DST coverage gap:** no test on a DST-transitioning time zone. Correctness rests on Foundation calendar arithmetic (sound), but unproven by automation. Add a test in Batch 1 or 3.
3. **Transient retain pattern (F-05):** `onTermination → task → continuation` chain resolves at termination; matches the accepted Ollama pattern — monitor only.
4. **Test-host side effect (macOS destination):** running tests launches the app host, which opens the local dev SwiftData store (reads + standard Core Data persistent-history housekeeping; no content mutation observed). Use simulator destinations in CI for isolation.
5. **F-05 / F-11 runtime behavior:** structurally verified only; live stop behavior and physical-device LAN prompt remain unproven (§16).
6. **Minor scope note:** cosmetic whitespace trims inside `SwiftDataService.init` (commit ea84611) — no behavioral effect.

**Environment limitations:** entitlements not inspectable (unsigned builds); no archive/Organizer privacy report; no physical device; no App Store Connect.

---

## 12. Remaining audit backlog

All original findings not addressed by the tranche (original severity preserved; "now" column = current recommended priority where it differs):

**P1 (remaining):**
| ID | Finding | Now |
|---|---|---|
| F-03 | No versioned SwiftData schema; `fatalError` crash loop on container failure | Batch 3 (before any schema change) |
| F-04 | Model-refresh upsert can wipe conversation→model relationships | Batch 3, reproduction-required first |
| F-06 | Reachability timer restarted off-main → polling dies after backoff | Batch 4 |
| F-07 | SwiftData models mutated on MainActor while the actor saves | Batch 4, TSan/reproduction first |
| F-08 | `AppleFoundationService.reachable()` can trap on unsupported devices | Batch 4 (cheap availability-check fix) |
| F-09 | API tokens in plaintext UserDefaults | Batch 5 (Keychain migration) |
| F-13 | Zero accessibility labels app-wide | Batch 2 |
| F-14 | Hardcoded fonts defeat Dynamic Type | later (separate from Batch 2 — layout reflow) |
| F-15 | Non-lazy message list | later, measurement-gated |
| F-16 | Main-thread base64 of all historical images | later, measurement-gated |

**P2 (remaining):** F-19 duplicate user prompt per turn; F-20 swallowed setup errors → stuck spinner (**Batch 1 candidate** per user guidance — small, high-value); F-21 think-cache fields persisted; F-22 conflicting delete rules; F-23 `generationTask` race; F-24 `reloadConversation` publish race; F-25 `CompletionsStore` off-main mutation (**Batch 1**); F-26 Apple provider discards history (**Batch 1**); F-27 SSE parser O(n²) + 1MB clamp; F-28 blanket ATS (**Batch 5b**); F-29 committed `Molten.app`; F-30 speech may leave device; F-31 touch targets (**Batch 2**); F-32 Reduce Motion (**Batch 2**); F-33 dark-mode colors + XR colorset warning (**Batch 2**); F-34 no localization (later); F-35 raw error UX; F-36 image re-decode (measurement); F-37 full-list swap hack; F-38 animated scroll per chunk (measurement); F-39 scenePhase/ping-interval (pairs with F-06 in Batch 4).

**P3 (remaining):** F-40 Mirror reflection; F-41 SSE edge cases; F-42 no request timeouts (**Batch 1**); F-44/F-48 Ollama token param shadowed + hardcoded literal (**Batch 1**); F-45 `CancellableHolder` race (Batch 4); F-46 AppStore state race (Batch 4); F-47 mid-stream kill loses content (Batch 3); F-49 Accessibility.plist placeholders; F-50 encryption declaration (compliance first); F-51 no CI (recommended alongside/after Batch 1); F-52 ChatView_iOS keyboard quirks; F-53 iPad drawer layout; F-54/F-55/F-56/F-57 dead-code/typo cleanups (dedicated cleanup batch, after correctness work); F-58 iOS/macOS duplication; F-60 5-second voice polling.

**Observations (remaining):** O-01 hardcoded temperature; **O-02 default-model key mismatch (Batch 1)**; O-03 image-support heuristic; O-04 error bodies discarded; O-05 edit-trim semantics test; O-06 color-only status (**Batch 2**); O-07 unbounded fetches; O-08 entitlement duplication; O-09 no DEBUG structure; O-10 concurrency debt (Batches 4/5); O-11 README inaccuracies; O-12 iOS 26 floor.

---

## 13. Recommended next batches

The user-proposed ordering was assessed against current evidence and **kept unchanged** — nothing in this review re-ranks it (the one addition is the delete-error-path micro-fix slotted into Batch 1).

### Batch 1 — Small correctness
- **Findings:** F-20, F-25, F-26, F-42, F-44+F-48, O-02, + delete-error-path micro-fix (§11 risk 1) and a DST day-deletion test (§11 risk 2).
- **Why now:** all XS/S, mostly flagged quick-fix candidates in the audit; they remove user-visible defects (stuck spinner, stateless Apple chat, ignored token settings, unpersisted default model) with no schema or compliance exposure; builds on the existing test target.
- **Prerequisites:** none (test target exists).
- **Effort:** S overall. **Regression risk:** low. **Migration planning:** no. **Physical device:** no (token/Ollama behavior optionally verifiable against local Ollama).
- **Tests to add with the change:** throwing-service stub → `.error` state (F-20); Apple provider multi-turn prompt includes history (F-26); request carries configured timeouts (F-42); token-only config reaches OllamaKit and no hardcoded literal remains (F-44/F-48); default model persists across simulated relaunch (O-02); delete-throws-does-not-clear-selection; DST-transition day delete (America/Los_Angeles).
- **Acceptance criteria:** all new tests green on macOS + iOS Simulator; Debug+Release builds succeed with 0 new warnings; `grep` confirms no `"okki"`-style literal (value not to be printed in any commit).
- **Excluded:** Keychain (F-09), ATS (F-28), schema changes, concurrency refactors, dead-code cleanup.

### Batch 2 — Accessibility quick wins
- **Findings:** F-13, F-31, F-32, F-33, O-06.
- **Why now:** zero accessibility support is a P1 App Store/quality gap; these are mechanical, low-risk, and independent of correctness work.
- **Prerequisites:** none. **Effort:** S–M. **Regression risk:** low (F-31 touch-target padding can shift layout slightly — visual check). **Migration:** no. **Physical device:** recommended (VoiceOver on device).
- **Tests:** Accessibility Inspector pass; reduce-motion/dark-mode manual matrix; optional snapshot check.
- **Acceptance:** every icon-only control labeled; hit targets ≥44pt; no `repeatForever` under Reduce Motion; dark-mode think-bar/unreachable banner visible; connection status has icon + text.
- **Excluded:** Dynamic Type (F-14) and localization (F-34) — deliberately separate due to layout reflow scope.

### Batch 3 — Persistence preparation
- **Findings:** F-03 (+ migration fixture tests) first; then, **separately and only after reproduction**, F-04, F-21, F-22, F-47.
- **Why now:** the next schema-touching fix (F-21 transients, F-22 rules) is unsafe without versioning; F-04's upsert-wipe is medium-confidence and needs proof before changing refresh logic.
- **Prerequisites:** Batch 1 (stable base); reproduction evidence for F-04/F-22 (loop `loadModels()`, inspect `conversation.model`; delete-models cascade probe).
- **Effort:** L. **Regression risk:** medium–high. **Migration planning:** **required** — VersionedSchema v1 capturing the shipped schema, migration plan, fixture stores, graceful-failure path replacing `fatalError`. **Physical device:** no.
- **Tests:** fixture-store open/migrate tests; fetch-or-update model refresh test; delete-rule test; stale `done=false` sanitization test.
- **Acceptance:** v1.0.1-era fixture store opens under the new plan; no data loss in refresh/delete tests; container-corruption boots gracefully.
- **Excluded:** any schema change not covered by the versioning plan; CloudKit/sync (n/a).

### Batch 4 — Concurrency / reachability
- **Findings:** F-06, F-23, F-24, F-45, F-46, F-08 (availability check), F-39 (scenePhase/ping apply); **F-07 only after TSan reproduction**.
- **Why now:** F-06 is a user-visible "permanently offline" bug; these are concentrated in AppStore/ConversationStore and share a testing approach.
- **Prerequisites:** Batch 1; TSan run for F-07/F-45/F-46 evidence. **Effort:** M–L. **Regression risk:** medium. **Migration:** no. **Physical device:** no (energy delta for F-39 = measurement).
- **Tests:** backoff math + timer-restart-on-main tests; rapid-send single-stream test; reload ordering test with instant mock provider; availability-check test for F-08.
- **Acceptance:** polling recovers after server restart without relaunch; TSan clean on streaming session; scenePhase stops/starts timer.
- **Excluded:** provider DI redesign (minimal seams only), UI changes.

### Batch 5 — Secrets / network policy (two sequenced sub-batches)
- **5a — F-09:** UserDefaults→Keychain migration (**copy-then-delete**), `SecureField`, warning on non-loopback HTTP endpoints carrying a token.
- **5b — F-28:** ATS scoping decision (`NSAllowsLocalNetworking` vs exception domains) — documented interaction with 5a: tokens over plaintext non-loopback HTTP must be gated regardless of ATS choice; review notes updated to match.
- **Why now (after Batches 1–4):** privacy-first product shipping plaintext tokens is the largest remaining trust risk, but the migration is safer once concurrency/persistence behavior is stable and tested.
- **Prerequisites:** Batches 1–3. **Effort:** M. **Regression risk:** medium (migration must be idempotent; ATS narrowing can break remote-HTTP users — compatibility matrix required). **Migration planning:** yes (defaults keys; one-time copy-then-delete). **Physical device:** recommended (LAN + remote endpoint matrix).
- **Tests:** migration test (values moved, old keys deleted, idempotent re-run); Authorization header still sent; ATS matrix (localhost, .local, LAN IP, remote HTTP/HTTPS).
- **Excluded:** F-50 (separate compliance sign-off), dependency upgrades.

---

## 14. Immediate next recommendation

**Implement Batch 1 — Small correctness.** Rationale: it is the only batch composed entirely of confirmed, low-risk, user-visible defect fixes with no schema, compliance, or concurrency-exposure; it leverages the test target this tranche created; and it clears the quick-fix backlog so Batch 2+ can proceed without small items constantly interleaving. It also absorbs the two follow-up risks this review found (delete error path, DST test) at negligible cost.

---

## 15. Suggested prompt for the next coding-agent batch

```
Implement Batch 1 (Small correctness) from IOS_REMEDIATION_STATUS.md §13 in
/Users/eplt/SCM/molten. Findings in scope, and ONLY these: F-20, F-25, F-26,
F-42, F-44+F-48, O-02, plus (a) the day-delete error-path micro-fix from §11
(don't clear selection / surface an error if SwiftDataService deletion throws)
and (b) one DST-transition day-deletion test (e.g. America/Los_Angeles
spring-forward day) in MoltenTests/DayDeletionTests.swift.

Hard constraints:
- Do not modify SwiftData model declarations or introduce schema migrations.
- Do not change UserDefaults key names; do not implement Keychain migration.
- Do not touch ATS, entitlements, Info.plist usage descriptions, privacy
  manifests, deployment targets, bundle ID, signing, or Package.resolved.
- Do not refactor singletons/provider dispatch; do not delete dead code;
  do not reformat unrelated files; no new dependencies.
- Preserve existing behavior except where correcting the listed defects.
- Treat the status report as evidence to verify, not truth: inspect each
  relevant source path before editing.

Preflight (run and report before editing; stop and ask if unexpected):
pwd; git status --short; git branch --show-current; git rev-parse HEAD;
git log -1 --oneline. Expected: repo /Users/eplt/SCM/molten, branch
audit/ios-review (or the approved working branch), HEAD at ea84611 or a
documented successor. Do not modify main; do not push/merge/rebase/amend.

Per-finding guidance:
- F-20: wrap ConversationStore.sendPrompt's setup Task in do/catch ->
  handleError on MainActor; test with a throwing fake/stub path asserting
  conversationState becomes .error.
- F-25: make CompletionsStore mutations @MainActor (or hop via MainActor.run);
  verify with Main Thread Checker reasoning / a launch-path test if practical.
- F-26: AppleFoundationService.chatStream must send the full formatted
  multi-turn prompt (the `prompt` already built) instead of only the last user
  message; test that a two-turn history produces a request/prompt containing
  both turns.
- F-42: set explicit timeouts on SwamaService getModels/chat/chatStream
  (e.g. connect ~10s; generous resource timeout for local inference); test
  configuration presence, not live black-hole ports.
- F-44+F-48: OllamaService.initEndpoint must honor the bearerToken parameter
  (fall back to UserDefaults) and pass it on the default-localhost path;
  delete the hardcoded default token literal (do not print its value anywhere,
  including commit messages). Test: token-only configuration is used.
- O-02: unify on one default-model key (keep the existing Settings key;
  persist on change; read at launch where selection is initialized). Do NOT
  rename keys — fix read/write wiring. Test: set -> simulated relaunch ->
  selection restored.

Commit structure: one commit per finding (or per tightly-related pair, e.g.
F-44+F-48), each preceded by `git diff` self-review and `git diff --check`.

Verification (all required; record exact commands and results):
- xcodebuild -resolvePackageDependencies (must stay exit 0, lockfile unchanged)
- xcodebuild build -scheme Molten -destination 'platform=macOS'
  -configuration Debug and Release, CODE_SIGNING_ALLOWED=NO
- xcodebuild build -scheme Molten -destination
  'platform=iOS Simulator,name=iPhone 17,OS=26.5' Debug and Release
- xcodebuild test -scheme Molten on macOS AND that iOS Simulator destination
  (all pre-existing + new tests green; report executed counts)
- prove 0 new warnings on changed lines (intersect warning locations with the
  diff's added lines)
- grep confirming the hardcoded token literal is gone (report only counts)
- git status --short (report final state; preserve CLAUDE.md,
  IOS_TECHNICAL_AUDIT.md, IOS_REMEDIATION_STATUS.md as untracked/committed per
  their existing state)

Finish with an evidence report: preflight output, commits created (hashes +
subjects), files changed per finding, tests added + results, build matrix
results, warning analysis, manual checks still required, and confirmation that
no out-of-scope files were modified. Stop there; do not start Batch 2.
```

---

## 16. Manual verification checklist

| # | Check | Finding | How | Status |
|---|---|---|---|---|
| 1 | Local Network prompt on fresh install | F-11 | Delete app from a physical iPhone; install build; configure a LAN Ollama/Swama URL; expect the system prompt with the new wording | **REQUIRED — not done** |
| 2 | LAN connection success after Allow (and failure mode after Deny) | F-11 | same session; verify chat works; document Deny-path UX | **REQUIRED — not done** |
| 3 | Stop behavior — Swama | F-05 | long generation vs Swama/OpenAI-compatible server → tap Stop → server logs client disconnect promptly; tokens stop; repeat ×10 (no orphaned connections via nettop/Instruments) | **REQUIRED — not done** |
| 4 | Stop behavior — Apple Foundation | F-05 | same with the Apple provider mid-chunked-response | **REQUIRED — not done** |
| 5 | Archive privacy report | F-10 | Xcode Archive → Organizer → privacy report shows the manifest with UserDefaults/CA92.1 | recommended — not done (no archive run) |
| 6 | App Store Connect privacy labels | F-30 | confirm labels disclose speech recognition's possible Apple-network path, or force on-device recognition first | **REQUIRED before next submission** |
| 7 | Export-compliance determination | F-50 | compliance sign-off, then add `ITSAppUsesNonExemptEncryption` | blocked on compliance |
| 8 | VoiceOver walk-through | (pre-Batch 2 baseline / post-Batch 2 gate) | chat send/stop/edit/copy/record flows on device | required if accessibility work is next |
| 9 | Day-delete UI smoke | F-01 | create chats on 3 days; long-press a day header → delete; confirm only that day disappears and open chat survives when from another day | recommended (logic is test-covered; UI path not exercised) |

---

## 17. Final recommendation

**The current branch is ready after the specified manual checks.** No merge-blocking defects were found in the remediation: the P0 data-loss bug is fixed and regression-tested on two platforms, the macOS build is restored and reproducible, privacy manifest and purpose strings ship in built products, sensitive logging is eliminated, and a real test suite runs green. The branch should not merge without: (1) physical-iPhone verification of F-11 (LAN prompt/connection — if denied silently, it is a P0 for iOS and must be re-examined before release), (2) live F-05 stop-behavior verification against Swama and Apple providers, and (3) the archive privacy report. After those pass, `audit/ios-review` is mergeable, and Batch 1 can begin immediately on the follow-on branch.
