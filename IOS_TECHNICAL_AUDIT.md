# Molten — iOS Technical Audit

**Review date:** 2026-08-01
**Repository:** `/Users/eplt/SCM/molten` @ HEAD `af7ba46` ("Release v1.0.1"), branch `audit/ios-review`
**Auditor role:** senior iOS engineer / release reviewer / cautious maintainer
**Mode:** read-only Phase 1 audit — no production source modified, no dependencies updated, no persistence or project-setting changes

---

## 1. Executive summary

Molten is a SwiftUI multi-platform (macOS/iOS/iPadOS) chat client for locally hosted LLMs (Ollama, Swama, Apple Foundation Models), forked from the open-source Enchanted project. The codebase is small (~90 Swift files, one target), reasonably layered (UI → `@Observable` stores → services → SwiftData), and its core streaming design is thoughtful. However, the audit found **one confirmed data-loss defect, a macOS build that fails from a clean checkout, zero automated tests, no privacy manifest, and a cluster of privacy and App Store compliance gaps** that should be resolved before the next version ships.

Headline results:

- **P0 (1):** "Delete daily conversations" deletes the user's **entire** conversation history — the date parameter is ignored and the delete-all service call is invoked. Verified by direct reading (`ConversationStore.swift:85-94` → `SwiftDataService.swift:103-106`), and wired to a visible per-day context-menu action.
- **P1 (17):** including a macOS build broken at HEAD by dependency drift (KeyboardShortcuts 2.0.1 API rename; `Package.resolved` is gitignored so clean checkouts resolve fresh), missing app privacy manifest despite UserDefaults usage (required-reason API), missing `NSLocalNetworkUsageDescription` (iOS local-network connections can silently fail — the app's core use case), API tokens in plaintext `UserDefaults`, release-build logging of full prompts and base64 images, zero accessibility labels anywhere, no Dynamic Type support, unversioned SwiftData schema with a `fatalError` crash loop on migration failure, two streaming providers whose Stop button doesn't actually stop the stream, and no test target of any kind.
- **P2/P3/Observation (55):** correctness races, persistence hazards, SSE parser fragility, accessibility, performance, dead code, and release-process gaps.

The app compiles cleanly for iOS (0 Swift warnings in our build) and its shipped state is consistent with a working iOS App Store release. The **macOS platform build is currently broken for anyone resolving packages today**, which means the next release cannot be rebuilt reproducibly without first fixing dependency pinning.

**Overall recommendation:** *conditionally ready* for new feature work — do the small "Batch 0" stabilization first (build reproducibility, P0 fix, privacy manifest, local-network usage description, log scrubbing). None of those require architectural change, and all are verifiable. Larger work (schema versioning, test suite, accessibility pass) should be sequenced alongside the next feature cycle per §15–§16.

---

## 2. Audit scope and environment

**In scope:** full repository review (source, project settings, plists, entitlements, docs, scripts, git history); baseline build attempts; static review across correctness, persistence, networking, security/privacy, dependencies, UI/a11y, performance, architecture, testing, and App Store readiness; dependency and Apple-policy research with web access.

**Out of scope (by instruction):** any source modification, refactors, dependency/version changes, persistence or entitlement changes, dynamic runtime testing beyond building, App Store Connect inspection.

**Environment:**

| Item | Value |
|---|---|
| Host | Apple Silicon Mac (arm64) |
| Xcode | 26.6 (build 17F113) |
| SDKs installed | iOS 26.5 (23F81a), macOS 26.5, + watchOS/tvOS/visionOS 26.5 |
| Simulator runtimes installed | iOS 18.2, 18.5, 26.0, 26.1, 26.2, **26.4** (no 26.5 runtime) |
| Internet | Available (SPM resolution and web research succeeded) |
| Signing | Bypassed for builds (`CODE_SIGNING_ALLOWED=NO`) |

**Environment limitations (not repo defects):**
- `actool` (asset catalog compilation) requires a simulator runtime matching SDK build `23F81a` (iOS 26.5); the newest installed runtime is `23E244` (26.4). All iOS-SDK builds therefore fail at `CompileAssetCatalogVariant` *after* all Swift sources compile successfully. A fully provisioned machine (or installing the iOS 26.5 simulator runtime) would complete these builds.
- `xcodebuild` destination discovery initially could not see simulators due to a stale CoreSimulator framework (auto-updated during the session); `-sdk` direct builds were used instead.
- No device runs were performed; runtime behaviors marked "manual verification required" could not be exercised.

---

## 3. Git and repository status

- **Current branch:** `audit/ios-review` (created for this audit).
- **Working tree:** clean except `?? CLAUDE.md` (documentation file created earlier in this session; not production code). No pre-existing uncommitted changes.
- **History:** very shallow — 11 commits total. Release-driven (`Init` → build fixes → `Release build 2/3` → `v1.0.1`). Commit hygiene is loose (`fx`, `fx`, `fx`), and `scripts/release.sh` hardcodes `v1.0.1` in its commit message and tag.
- **Most-changed files** (change frequency signal): `project.pbxproj` (8), `OllamaService.swift` (4), `ConversationStore.swift`, `AppStore.swift`, `SwamaService.swift`, `MessageListVIew.swift`, `Chat.swift` (3 each). The services/stores layer is the churn zone — consistent with where most findings concentrate.
- **Tracked binary:** `git ls-files Molten.app` shows **29 tracked files** including a code-signed executable, with stale metadata (`CFBundleIdentifier=com.ondemandworld.Molten` capital-M, version `1.0.0`/build `3`) that does not match current source (`com.ondemandworld.molten`, `1.0.1`/`4`). See F-29.
- **`.gitignore` notes:** excludes `Package.resolved` (see F-18), does not exclude `*.app` or `.DS_Store` (a `.DS_Store` is tracked in `Molten/`), and deliberately excludes `QWEN.md` ("AI Assistant Context").

---

## 4. Build and test baseline

Exact commands (run 2026-08-01), from repo root:

| # | Command | Result |
|---|---|---|
| 1 | `xcodebuild -list -project Molten.xcodeproj` | OK. Targets: `Molten` (only). Configs: Debug, Release. Schemes: `Molten` (+ auto-exposed package schemes `KeyboardShortcuts`, `MarkdownUI`). SPM resolved 14 packages. |
| 2 | `xcrun simctl list runtimes` / `list devices available` | iOS runtimes 18.2–26.4; iPhone 16 family + iPads available. |
| 3 | `xcodebuild -showsdks` | iOS/macOS 26.5 SDKs present. |
| 4 | `xcodebuild build -scheme Molten -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'` | **Failed pre-compile** — no device matched (`OS=latest` → 26.5 runtime not installed). Environment. |
| 5 | `... -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.4'` and `'generic/platform=iOS Simulator'` | **Failed pre-compile** — xcodebuild enumerated only macOS destinations (stale CoreSimulator integration in this environment). Environment. |
| 6 | `xcodebuild build -scheme Molten -sdk iphonesimulator26.5 CODE_SIGNING_ALLOWED=NO` | **All Swift compiled: 0 Swift warnings.** Failed only at `CompileAssetCatalogVariant`: `error: No simulator runtime version from ["22C150",…"23E244"] available to use with iphonesimulator SDK version 23F81a`. Environment (see §2). |
| 7 | `xcodebuild build -scheme Molten -sdk iphoneos26.5 CODE_SIGNING_ALLOWED=NO` | Same as #6: Swift clean; asset-catalog step blocked by the same runtime/SDK mismatch. Environment. |
| 8 | `xcodebuild build -scheme Molten -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | **BUILD FAILED — repository defect (F-02):** `Molten/Application/MoltenApp.swift:39:18: error: value of type 'ApplicationEntry' has no member 'onGlobalKeyboardShortcut'` (+ `:39:90: cannot infer contextual base in reference to member 'keyDown'`). 2 asset-catalog warnings (see below). |

**Asset-catalog warnings (both platforms, from repo content):**
`Assets.xcassets/Colors/bgCustom.colorset` (dark variant) references `systemBackgroundColor` declared for the XR platform; actool warns it "may appear differently at runtime" / "older systems will not see the expected value." Minor, but real (tracked under F-33 dark-mode cluster).

**Tests:** there is **no test target** — `project.pbxproj` has exactly one `PBXNativeTarget`, zero XCTest entries; no `*Tests*` directories exist. `xcodebuild test -scheme Molten` has nothing to execute (the scheme's TestAction relies on `shouldAutocreateTestPlan`). The README's `xcodebuild test -scheme Molten` instruction is therefore misleading. Nothing was skipped or flaky because nothing exists.

**Static analysis / lint:** none configured (no SwiftLint/swift-format; no `SWIFT_TREAT_WARNINGS_AS_ERRORS`). `xcodebuild analyze` was not run: the macOS configuration fails to compile (F-02) and the iOS configurations cannot link through actool in this environment (§2). This is recorded as a gap, not a pass.

**Warning summary:** 0 Swift compiler warnings in the iOS configurations; 2 actool warnings (asset catalog). Warnings were neither hidden nor suppressed.

---

## 5. Project inventory

| Dimension | Finding |
|---|---|
| **Targets** | One app target `Molten` (multi-platform: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `TARGETED_DEVICE_FAMILY = "1,2"`). No extensions, widgets, watch targets, or test targets. |
| **Schemes** | `Molten` (shared). Debug/Release configurations. |
| **Languages/UI** | 100% Swift; 100% SwiftUI (no UIKit view controllers; UIKit used only for haptics, pasteboard, image codecs, keyboard notifications). No Objective-C. |
| **Deployment targets** | `MACOSX_DEPLOYMENT_TARGET = 26.0`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (pbxproj). README claims macOS 14+/iOS 17+ — **outdated** (O-11). |
| **Swift mode** | `SWIFT_VERSION = 5.0` with `SWIFT_STRICT_CONCURRENCY = complete` (Swift 6-ready checking). |
| **Versions** | `MARKETING_VERSION = 1.0.1`, `CURRENT_PROJECT_VERSION = 4` — consistent across Debug/Release today; committed binary proves historical drift (F-29). |
| **Dependency management** | SPM only (14 resolved packages incl. transitives). No CocoaPods/Carthage/vendored frameworks, except the committed `Molten.app` bundle which vendors an Alamofire privacy-manifest bundle. |
| **Persistence** | SwiftData (`ConversationSD`, `MessageSD`, `LanguageModelSD`, `CompletionInstructionSD`) via an actor-owned `ModelContext`; `UserDefaults`/`@AppStorage` for settings **including API tokens**. No Keychain, no files-of-note, no CloudKit, no remote backend. |
| **Networking** | Ollama via OllamaKit (Combine→AsyncStream, Alamofire transitively); Swama via hand-rolled `URLSession` SSE parsing (OpenAI-compatible); Apple Foundation Models via `FoundationModels.LanguageModelSession` (on-device). All endpoints user-configured local servers; default `http://localhost:11434` / `http://localhost:28100`. |
| **Auth / subscriptions / notifications / deep links / analytics / crash reporting** | None. Bearer tokens optional for user servers. No IAP, no push, no URL schemes, no analytics/crash SDKs (verified by import grep). |
| **Build settings & signing** | Automatic signing; `CODE_SIGN_ENTITLEMENTS` = `Molten/Molten.entitlements` (Release, empty dict) / `MoltenDebug.entitlements` (Debug, user-selected-files read-only). Capabilities generated via `ENABLE_*` keys for both configs: app sandbox, hardened runtime, outgoing network, audio input, user-selected files readonly — final signed entitlement set verified minimal by the security review. No `.xcconfig` files. |
| **Privacy manifests** | **None for the app target** (F-10). Only Alamofire's own manifest exists (inside the committed binary). |
| **Info.plist** | `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_KEY_*` (mic + speech usage descriptions present and accurate; launch screen/status bar generated for iOS). Hand-written `Molten/Info.plist` adds `NSAccessibilityUsageDescription`, `NSAllowsArbitraryLoads = true` (F-28), and an inert `com.apple.security.network.client` key (entitlement keys have no effect in Info.plist — O-08). **Missing: `NSLocalNetworkUsageDescription` (F-11), `ITSAppUsesNonExemptEncryption` (F-50).** |
| **Scripts / CI / lint** | No CI (no `.github/`). `scripts/release.sh`: interactive git commit+tag+push with `v1.0.1` hardcoded, no build/test/archive/notarize steps. No lint/format tooling. |
| **Documentation** | README (partly outdated), ARCHITECTURE.md (accurate high-level), CONTRIBUTING.md, ~15 release/App-Store-process docs. `Accessibility.plist` ships with template placeholder text (F-49). |
| **Dead/excluded files** | 4 Swift files are not members of the build target (verified via pbxproj reference count = 0): `EnchantedApp.swift` (duplicate `@main` landmine), `Header.swift` (would not compile), `Sidebar_macOS.swift`, `NSClipboardItem.swift`. Further compiled-but-unreachable code inventoried in F-56. |

---

## 6. Current architecture and data-flow map

Layered, singleton-wired. See `ARCHITECTURE.md` for the authors' own description (broadly accurate).

```
┌──────────────────────────────── UI (SwiftUI) ────────────────────────────────┐
│ MoltenApp (@main) → ApplicationEntry → Chat | Voice(never shown)             │
│   UI/Shared (both platforms)   UI/macOS (panel, menus, completions editor)   │
│   UI/iOS (ChatView_iOS) — platform conditionals (#if os(macOS)) throughout   │
└──────────────┬───────────────────────────────────────────────────────────────┘
               │ reads/writes @Observable state
┌──────────────▼─────────── Stores (@Observable, .shared singletons) ──────────┐
│ ConversationStore (@unchecked Sendable; @MainActor UI state)                 │
│   sendPrompt → getProvider(model.modelProvider) → chatStream                 │
│   handleReceive (array buffer + Throttler 0.15s) → handleComplete (analytics)│
│ LanguageModelStore (discovery/prefix O:/S:/A:)  CompletionsStore  AppStore   │
│   AppStore: Timer-driven reachability polling, 10s cache, exp. backoff       │
└──────────────┬───────────────────────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────── Services ─────────────────────────────────┐
│ ModelProviderProtocol: reachable() / getModels() /                           │
│   chatStream() -> AsyncThrowingStream<ChatCompletionResponse>                │
│  ├ OllamaService (OllamaKit; Combine→AsyncStream; onTermination cancel ✔)    │
│  ├ SwamaService (URLSession SSE; byte-by-byte parse; no producer cancel ✘)   │
│  └ AppleFoundationService (FoundationModels; simulated streaming; no cancel) │
│ SwiftDataService (actor; owns ModelContainer/ModelContext; autosave off)     │
│ SpeechService, HapticsService, Clipboard, SpeechRecognizer (mic+speech)      │
└──────────────┬───────────────────────────────────────────────────────────────┘
               │
┌──────────────▼────── Persistence ──────┐   ┌──── External (local only) ────┐
│ SwiftData store (no versioned schema): │   │ Ollama  http://localhost:11434 │
│  ConversationSD ⇄ MessageSD (cascade)  │   │ Swama   http://localhost:28100 │
│  ConversationSD ⇄ LanguageModelSD      │   │ Apple Foundation Models (OS)   │
│ UserDefaults: settings + API tokens(!) │   │ SFSpeechRecognizer (may use    │
└────────────────────────────────────────┘   │  Apple network — F-30)         │
                                             └────────────────────────────────┘
```

**Major flows:**
1. **Chat send:** `ChatView` → `ConversationStore.sendPrompt` (@MainActor: builds history incl. base64 images, creates user+assistant `MessageSD`) → provider `chatStream` → per-chunk `handleReceive` (buffered, throttled UI flush) → `handleComplete` (analytics, persist) or `handleError`. Cancellation via `generationTask` (consumer side only — F-05).
2. **Model discovery:** launch/refresh → per provider `reachable()` → `getModels()` → upsert `LanguageModelSD` (unique `name`; relationship-wipe hazard F-04).
3. **Reachability:** `AppStore` `Timer` (15s macOS / 30s iOS default) → all providers, 10s cache, backoff 30s→300s (default localhost) or 10s→60s (user URL); timer-lifecycle bug F-06; never pauses in background (F-39).
4. **macOS panel mode:** `PanelManager` (NSApplicationDelegateAdaptor) + `FloatingPanel`; ⌘⌥K global shortcut via KeyboardShortcuts package — currently uncompilable against resolved 2.0.1 (F-02).

**Structural observations:** every store/service is a `nonisolated(unsafe) static let shared` singleton; only `SwiftDataService` is injected (into `ConversationStore`), while providers are hardcoded `.shared` lookups — the core flows are not unit-testable as-is (F-17, O-10).

---

## 7. Positive findings and things that should be preserved

- **Streaming design intent is sound and documented:** array buffer + `Throttler` instead of O(n²) string concatenation, with comments explaining the UI-freeze rationale (`ConversationStore.swift:31-39`), `weak self` in long-lived closures, and `Task.isCancelled` checks in all three streaming loops.
- **`OllamaService.chatStream` correctly wires `continuation.onTermination` to cancel the underlying subscription** (`OllamaService.swift:209-211`) — the pattern F-05 should replicate.
- **Provider abstraction is clean:** `ModelProviderProtocol` unifies three backends behind one streaming interface; hand-written `ChatMessage`/`ContentType` Codable is defensively tolerant of OpenAI-compatible server variance (`ModelProviderProtocol.swift:36-132`).
- **SwiftData hygiene basics are right:** actor isolation with a serial model executor, `autosaveEnabled = false` with explicit saves, `@Attribute(.externalStorage)` for message images (`MessageSD.swift:101`).
- **Privacy posture is genuine:** zero analytics/tracking/crash SDKs; no telemetry endpoints; iOS pasteboard is write-only (copy buttons — no read, so no paste-banner issue); mic buffers are never persisted; permission prompts are lazy on user tap, not at launch.
- **Entitlements are minimal and correct** in the signed binary (sandbox + hardened runtime + network client + audio input + user-selected-files readonly) for both configs.
- **Reachability hardening design** (2s timeouts per provider, 10s cache, differentiated backoff) is the right shape — implementation bugs (F-06, F-46) are fixable without redesign.
- **`#Preview` blocks on nearly every view**, and the Markdown theme uses proper light/dark palettes via `Color(light:dark:)`.
- **`AnalyticsFooterView` adapts to size classes** — evidence the codebase knows the right pattern; it's just not applied elsewhere (F-53).

---

## 8. Findings summary by severity

**P0 — release blockers / data loss (1)**

| ID | Title | Category | Quick fix |
|---|---|---|---|
| F-01 | "Delete daily conversations" deletes ALL conversations | correctness/persistence | yes |

**P1 — high impact (17)**

| ID | Title | Category | Quick fix |
|---|---|---|---|
| F-02 | macOS build fails from clean checkout (KeyboardShortcuts 2.0.1 drift) | build/dependencies | no (pin + rename call) |
| F-03 | No versioned SwiftData schema; container failure = `fatalError` loop | persistence | no |
| F-04 | Model refresh upsert can wipe conversation→model relationships | persistence | no |
| F-05 | Stop doesn't stop Swama/Apple streams (no producer cancellation) | correctness | yes |
| F-06 | Reachability timer restarted off-main → polling silently dies | correctness | no |
| F-07 | SwiftData models mutated on MainActor while actor saves them | correctness | no |
| F-08 | `AppleFoundationService.reachable()` can trap on unsupported devices | correctness | no |
| F-09 | API tokens stored in plaintext UserDefaults; plain TextField entry | security | no |
| F-10 | No app privacy manifest despite UserDefaults (required-reason API) | app-store | yes |
| F-11 | Missing `NSLocalNetworkUsageDescription` — iOS LAN connections can fail silently | app-store/correctness | yes |
| F-12 | Release builds log full prompts + base64 images (41 unguarded prints) | privacy | yes |
| F-13 | Zero accessibility labels/hints/traits in the entire app | ui-a11y | yes |
| F-14 | Hardcoded point-size fonts everywhere defeat Dynamic Type | ui-a11y | no |
| F-15 | Message list is non-lazy; full re-render on completion | performance | no |
| F-16 | Main-thread base64 encoding of ALL historical images on every send | performance | no |
| F-17 | No test target; zero automation around high-risk flows | testing | no |
| F-18 | `Package.resolved` gitignored + 3 branch-pinned forks → unreproducible builds | build/dependencies | no |

**P2 (21):** F-19 duplicate user prompt per turn; F-20 setup errors swallowed → stuck spinner; F-21 think-cache fields persisted (2–3× storage); F-22 conflicting delete rules on Conversation↔Model; F-23 `generationTask` race on rapid sends; F-24 `reloadConversation` publish race drops leading tokens; F-25 `CompletionsStore` mutates observable state off-main; F-26 Apple provider discards conversation history; F-27 SSE parser O(n²) + destructive 1MB clamp; F-28 `NSAllowsArbitraryLoads` blanket ATS disable; F-29 signed `Molten.app` committed to git (stale bundle id/version); F-30 speech recognition may use Apple's network (privacy-claim conflict); F-31 touch targets 12–22pt; F-32 no Reduce Motion handling with infinite animations; F-33 hardcoded black/dark-mode-breaking elements + XR color warning; F-34 no localization infrastructure; F-35 raw `localizedDescription` error UX; F-36 image re-decoded per body evaluation; F-37 full-list swap invalidation hack; F-38 animated scroll on every streamed chunk; F-39 polling ignores `scenePhase`; ping-interval setting never applies.

**P3 (21):** F-40 Mirror-reflection response extraction; F-41 SSE spec edge cases; F-42 no request timeouts (60s default); F-43 day-delete predicate matches exact instant; F-44 Ollama bearer-token parameter shadowed/ignored; F-45 `CancellableHolder` unsynchronized; F-46 AppStore backoff state data race; F-47 mid-stream kill loses content + stuck `done=false` rows; F-48 hardcoded default token literal in source; F-49 `Accessibility.plist` template placeholders ship in bundle; F-50 no `ITSAppUsesNonExemptEncryption`; F-51 no CI; F-52 ChatView_iOS keyboard/focus quirks; F-53 iPad = large iPhone (300pt drawer); F-54 `EnchantedApp.swift` duplicate `@main` landmine; F-55 four files outside target (one uncompilable); F-56 compiled-but-unreachable code (Voice flow, helpers); F-57 filename/type typos; F-58 iOS/macOS chat logic duplicated; F-59 profanity/debug prints; F-60 Settings polls voice list every 5s.

**Observations (12):** O-01 hardcoded `temperature: 0.0`; O-02 default-model setting never persists (key mismatch); O-03 image-support name heuristic mislabels text models; O-04 HTTP error bodies discarded; O-05 edit-trim semantics need tests; O-06 color-only connection status; O-07 unbounded fetches/history; O-08 entitlement/plist duplication; O-09 no `#if DEBUG` structure anywhere; O-10 concurrency-hygiene debt (`DispatchQueue.main.async`, `nonisolated(unsafe)`); O-11 README inaccuracies (targets, test command); O-12 iOS 26.0 minimum excludes older devices (market decision).

---

## 9. Detailed findings

### P0

**F-01 — "Delete daily conversations" deletes the entire history** | P0 | Confidence: high | Category: correctness/persistence
Evidence: `ConversationStore.swift:85-94` — `func deleteDailyConversations(_ date: Date)` never uses `date`; it calls `swiftDataService.deleteConversations()` — the no-argument delete-all (`SwiftDataService.swift:103-106`, `modelContext.delete(model: ConversationSD.self)`). Wired to the per-day context-menu action (`Chat.swift:144,155` → `ConversationHistoryListView` day-header menu). The date-aware overload `deleteConversations(_ date:)` (`SwiftDataService.swift:113-116`) has zero callers and its own predicate is broken (F-43).
Impact: any user who taps the per-day "delete" silently loses **all** conversations. Data loss on a shipped feature path.
Why it matters: worst-class defect for a chat app; trivially triggered; no undo.
Fix: call a day-ranged delete (`startOfDay ..< startOfNextDay` on `createdAt`), then `saveChanges()` and reload; only clear selection if it was among the deleted rows. Fix F-43 together.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: unit test — conversations on two dates, delete one day, assert survivor; manual long-press day header → delete → other days remain.

### P1

**F-02 — macOS build fails from a clean checkout** | P1 (P0 if macOS is a shipping channel) | Confidence: high | Category: build/dependencies
Evidence: clean resolve picks KeyboardShortcuts **2.0.1** (requirement `upToNextMajorVersion` from 2.0.0 in pbxproj); 2.0.1's `ViewModifiers.swift` exposes only `onKeyboardShortcut` (verified in the resolved checkout). `MoltenApp.swift:39` calls `.onGlobalKeyboardShortcut(..., type: .keyDown)` (1.x name) → `error: value of type 'ApplicationEntry' has no member 'onGlobalKeyboardShortcut'` (reproduced: §4, command 8). Ironically the dead legacy file `EnchantedApp.swift:29` already uses the new name. iOS compiles because the call sits in `#if os(macOS)`.
Impact: no one can build the macOS app from a clean clone today; the shipped binary was built against older, unrecorded pins. Blocks any macOS release or CI.
Fix: (a) commit `Package.resolved` (F-18); (b) rename the call to `onKeyboardShortcut`; (c) pin KeyboardShortcuts to a known-good exact version.
Effort: S | Regression risk: low | Quick-fix candidate: no (touches dependency pins — do deliberately)
Verification: delete DerivedData + `Package.resolved`; `xcodebuild -destination 'platform=macOS' build` succeeds.

**F-03 — No versioned SwiftData schema; container failure is a `fatalError` crash loop** | P1 | Confidence: high | Category: persistence
Evidence: `SwiftDataService.swift:19-33` builds `Schema([...])` ad hoc; repo-wide grep finds no `VersionedSchema`/`SchemaMigrationPlan`; line 31 `fatalError("Could not create ModelContainer: \(error)")` runs on first touch of `.shared`, i.e., at launch. Analytics fields on `MessageSD` were evidently added post-hoc.
Impact: the *next* schema change risks lightweight-migration failure for existing App Store users → launch crash loop with no recovery; store corruption = permanent brick.
Why it matters: existing users' data is the asset; one careless property add can wipe the install base.
Fix: introduce `VersionedSchema` per release + `SchemaMigrationPlan`; on container failure, fall back to in-memory + quarantine/rename the store and notify, never `fatalError`.
Effort: L | Regression risk: medium | Quick-fix candidate: no
Verification: fixture stores from each shipped schema open under migration tests; corrupted-store file boots gracefully.

**F-04 — Model refresh upsert can wipe conversation→model relationships** | P1 | Confidence: medium | Category: persistence
Evidence: `LanguageModelSD.swift:13` `@Attribute(.unique) var name`; `LanguageModelStore.loadModels()` (called at launch, on new chat `Chat.swift:88`, and on Settings save) inserts freshly constructed `LanguageModelSD` objects with the default empty `conversations` relationship; SwiftData resolves unique-constraint conflicts by upsert, overwriting stored property values with the new object's (documented upsert pitfall).
Impact: after any refresh, conversations can lose `model` → `getProvider(for:)` returns nil → old chats fail with "Unknown model provider".
Fix: fetch-or-update by name (mutate existing rows); insert only genuinely new names.
Effort: S | Regression risk: medium | Quick-fix candidate: no
Verification: test — conversation with model M, run `loadModels()` twice, refetch, assert `model != nil`. (Also listed §11 — confirm upsert behavior empirically first.)

**F-05 — Stop doesn't stop Swama/Apple streams** | P1 | Confidence: high | Category: correctness
Evidence: `grep onTermination Molten/Services/*.swift` → only `OllamaService.swift:209`. `SwamaService.chatStream`'s inner `Task` has no `continuation.onTermination` (its `Task.isCancelled` check never fires); same in `AppleFoundationService.swift:53-156`. `ConversationStore.stopGenerate` cancels only the consumer task.
Impact: Stop/navigate-away leaves the HTTP stream downloading and the server generating until it finishes; orphan tasks accumulate across stop/start cycles; wasted CPU/bandwidth/battery.
Fix: capture the inner task; `continuation.onTermination = { _ in task.cancel() }` — copy the Ollama pattern.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: start a Swama stream, cancel consumer, assert byte loop exits promptly; no orphan tasks after repeated stop/start.

**F-06 — Reachability timer restarted from a background task → polling silently dies** | P1 | Confidence: high | Category: correctness
Evidence: `AppStore.swift:74-112` — the timer closure spawns a `Task` that calls `stopCheckingReachability()`/`startCheckingReachability()`; `Timer.scheduledTimer` schedules on the *current* thread's run loop, which in the cooperative pool never runs. After ≥3 consecutive failures the replacement timer never fires. Cross-thread `invalidate()` is also unsafe.
Impact: once a provider goes down and backoff engages, `isReachable` can freeze (likely `false`) until app restart — the app shows "offline" forever even after the server returns. Duplicate timers possible on concurrent ticks.
Fix: perform timer lifecycle on the MainActor (`await MainActor.run {…}`) or replace with a `Task.sleep` loop / `AsyncTimerSequence`.
Effort: S | Regression risk: medium | Quick-fix candidate: no
Verification: stop server → wait for backoff → restart server → `isReachable` recovers without relaunch; single live timer. (Repro steps in §11.)

**F-07 — SwiftData models mutated on MainActor while the service actor saves them** | P1 | Confidence: medium | Category: correctness
Evidence: the `ModelContext` lives inside the `SwiftDataService` actor (`SwiftDataService.swift:11-38`), yet fetched instances are mutated from `@MainActor` code during streaming (`ConversationStore.swift` buffer flush ~318-322, content append ~447, analytics ~330-366, error flags ~456-458) concurrently with actor-side saves of the same instances (including background-priority save tasks).
Impact: `PersistentModel` instances touched from two executors = data races: corrupted writes, faults, crashes — precisely under streaming load.
Fix: give the UI its own main-actor `ModelContext` from the shared container, or route all mutations through the actor and publish snapshots.
Effort: L | Regression risk: high | Quick-fix candidate: no
Verification: Thread Sanitizer over a streaming session shows no SwiftData races; stop/start stress test.

**F-08 — `AppleFoundationService.reachable()` can trap on unsupported devices** | P1 | Confidence: medium-high | Category: correctness
Evidence: `AppleFoundationService.swift:19-29` — `_ = LanguageModelSession(); return true` under `#if canImport(FoundationModels)`, with no `SystemLanguageModelSession.availability` check. `LanguageModelSession()` is non-failable and traps when Apple Intelligence is unavailable. Runs from the 15–30s poll (`AppStore.swift:179`) and every reachability gate; `getModels()` also lists the model unconditionally on canImport platforms.
Impact: on OS 26 devices without Foundation Models (unsupported hardware/region/Apple Intelligence disabled), a background poll can crash the app repeatedly; on supported devices it needlessly builds a session per poll.
Fix: check availability API; cache; return `false` when unavailable.
Effort: S | Regression risk: low | Quick-fix candidate: no (verify availability API semantics on both platforms)
Verification: run on an unsupported configuration/simulator; `reachable()` returns false without crashing.

**F-09 — API tokens in plaintext UserDefaults, entered via plain TextField** | P1 | Confidence: high | Category: security
Evidence: `Settings.swift:18,23` `@AppStorage("ollamaBearerToken"/"swamaApiKey")`; read at `OllamaService.swift:32`, `SwamaService.swift:39`; sent as `Authorization: Bearer` (`SwamaService.swift:81,121,151`); entered through `TextField` (visible text) at `SettingsView.swift:127,155`; zero Keychain usage repo-wide. Tokens can traverse plaintext `http://` to non-loopback hosts.
Impact: credentials persist in an unencrypted plist included in backups; shoulder-surfable entry; contradicts the privacy-first positioning.
Fix: Keychain (`kSecClassGenericPassword`, non-synced) + one-time migration that deletes the plaintext keys; `SecureField` in Settings; warn on non-loopback `http` endpoints carrying a token.
Effort: M | Regression risk: low | Quick-fix candidate: no
Verification: after migration, `defaults read com.ondemandworld.molten` shows no token; requests still authorized.

**F-10 — No app privacy manifest despite required-reason API usage** | P1 | Confidence: high | Category: app-store
Evidence: `grep -c xcprivacy Molten.xcodeproj/project.pbxproj` → 0; no app-level `PrivacyInfo.xcprivacy` anywhere. UserDefaults used in ~15 sites. Apple's required-reason API policy (enforced since May 2024, macOS included) requires declaring a reason — `CA92.1` (app accesses only its own defaults) fits. No file-timestamp/disk-space/boot-time APIs detected, so the manifest stays tiny.
Impact: submission friction/rejection risk; currently no `NSPrivacyTracking=false` declaration at all.
Fix: add `Molten/PrivacyInfo.xcprivacy` to the target: tracking=false, empty tracking domains, UserDefaults category with `CA92.1`.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: archive → Organizer privacy report shows the manifest; TestFlight upload passes automated checks.

**F-11 — Missing `NSLocalNetworkUsageDescription`** | P1 (potentially P0 for iOS LAN use) | Confidence: high (key absence verified; runtime impact needs device confirmation) | Category: app-store/correctness
Evidence: no `LocalNetwork`/`Bonjour` keys in Info.plist or pbxproj. iOS users must point the app at another machine's LAN IP (localhost only reaches the iPhone itself); iOS 14+ gates LAN connections behind the Local Network prompt, which requires this usage description — without it the prompt is suppressed and connections are denied.
Impact: on a fresh iOS install, the app's core function (talk to the user's Ollama/Swama server) can fail silently. Recurring App Review friction for local-network apps.
Fix: add `INFOPLIST_KEY_NSLocalNetworkUsageDescription` (e.g., "Molten connects to your local AI server (Ollama/Swama) on your network.") for iOS SDKs.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: **manual, physical iPhone** — fresh install, configure LAN URL, expect system prompt; connections succeed when allowed (see §11/§17).

**F-12 — Release builds log full prompts and base64 images** | P1 | Confidence: high | Category: privacy
Evidence: 41 `print(` sites, **0** `#if DEBUG` guards (both grep-verified). `SwamaService.swift:166-169` logs the request URL **and entire JSON body** (all user prompts + `data:image/jpeg;base64,…` payloads built in `ConversationStore.swift:202-226`); `PanelCompletionsVM.swift:49,125,130` prints prompts and full responses; `Accessibility.swift:35` prints text selected in third-party apps; `SpeechRecogniser.swift:60-64` includes `"denicd"`/`"wtf"` debug strings.
Impact: private conversations (and images, and other-apps' selected text) land in unified logs readable by same-user processes and captured by diagnostic exports; MB-scale log spam on hot paths. Directly contradicts PRIVACY.md.
Fix: delete payload logging; move remaining diagnostics to `os.Logger` with `privacy: .private` interpolation and DEBUG gating.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: Release build + `log stream --predicate 'process=="Molten"'` during a chat with image → no content appears.

**F-13 — Zero accessibility labels/hints/traits app-wide** | P1 | Confidence: high | Category: ui-a11y
Evidence: `grep -rn 'accessibilityLabel|accessibilityHint|accessibilityAddTraits' Molten --include='*.swift' | wc -l` → **0**. Icon-only buttons everywhere: menu/new-chat/photo/send/stop (`ChatView_iOS.swift:89-174`), copy (`CodeBlockView.swift:26-32`), dismiss (`SelectTextSheet.swift:26-30`), mic (`RecordingView.swift:40-60`).
Impact: VoiceOver announces raw symbol names ("paperplane fill button"); send vs stop-generation is indistinguishable. Effectively unusable with VoiceOver; below App Store accessibility expectations.
Fix: label every icon-only control; `.accessibilityHidden(true)` on decorative images; group the analytics footer as one element.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: VoiceOver walk-through of chat send/stop/edit/copy/record; Accessibility Inspector pass.

**F-14 — Hardcoded point-size fonts defeat Dynamic Type** | P1 | Confidence: high | Category: ui-a11y
Evidence: 24 active `.font(.system(size:))` uses across native chrome (e.g., `ChatView_iOS.swift:147`, `ConversationStatusView.swift:20`, `UnreachableAPIView.swift:21`, `SettingsView.swift:42/51/59/90`, `ConversationHistoryListView.swift:51/74`) and the Markdown body base fixed at `FontSize(14)` (`MarkdownColours.swift:41-42`).
Impact: Larger Text accessibility settings scale nothing; low-vision users cannot enlarge chat text — the app's entire content.
Fix: text styles (`.body/.subheadline/.caption`) or `@ScaledMetric`; tie the Markdown theme base to a scaled metric.
Effort: M | Regression risk: medium (layout reflow) | Quick-fix candidate: no
Verification: AX5 Dynamic Type on device; all screens scale without truncation.

**F-15 — Message list is non-lazy with full-list re-render on completion** | P1 | Confidence: high (code-verified; scale requires measurement) | Category: performance
Evidence: `MessageListVIew.swift:53-104` — `ScrollView { VStack { ForEach(messages) } }` (not `LazyVStack`), each row building `Markdown(content)` with Splash highlighting; plus the `messages = []; messages = currentMessages` swap hack (`ConversationStore.swift:158-161, 368-371`) forcing whole-list invalidation on completion.
Impact: long conversations instantiate and re-render every row; memory/CPU grow unbounded per conversation.
Fix: `LazyVStack` (keep `ScrollViewReader` + stable ids); mutate the model's `done` flag instead of swapping arrays.
Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: requires measurement — Instruments SwiftUI template, 500-message conversation, before/after body counts (§11).

**F-16 — Main-thread base64 encoding of all historical images on every send** | P1 | Confidence: high (code-verified; scale requires measurement) | Category: performance
Evidence: `sendPrompt` is `@MainActor` and performs JPEG re-encode of the new image (`ConversationStore.swift:198`), full-quality base64 (`:223`), and loops **all** prior messages re-encoding each stored image to base64 (`:202-218`) — per send, on the main thread.
Impact: UI hitch/freeze scaling O(image history) on every send in image-heavy chats.
Fix: assemble history + encode off-main; compress once at capture and cache the data-URL per message.
Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: Time Profiler sending in a 20-image conversation (§11).

**F-17 — No test target; zero automation around high-risk flows** | P1 | Confidence: high | Category: testing
Evidence: one `PBXNativeTarget` in pbxproj; no XCTest entries; no `*Tests*` directories; README test instruction is vacuous.
Impact: every fix in this audit ships unverified; streaming/persistence regressions reach users directly.
Fix: add `MoltenTests` unit target now (UI tests later); gate future CI on it; start with the suite in §13.
Effort: S (target) + M (suite) | Regression risk: low | Quick-fix candidate: no (the target itself is trivial; the value is the suite)
Verification: `xcodebuild test -scheme Molten -destination …` runs green with the starter suite.

**F-18 — Unreproducible builds: gitignored `Package.resolved` + branch-pinned forks** | P1 | Confidence: high (demonstrated live by F-02) | Category: build/dependencies
Evidence: `.gitignore` contains `Package.resolved`; `git ls-files | grep resolved` → empty. The resolved set shows `Magnet @ master`, `OllamaKit @ main`, `Splash @ master` (forks; research pass confirmed the pinned SHAs are *current* branch heads under the renamed `gluonfield/*` accounts — stable today, floating forever). KeyboardShortcuts floats within `2.x` and already broke the build (F-02).
Impact: a push to any of those branches silently changes what ships; rebuilds (yours, Apple's, auditors') differ from the archived binary. No CI to detect drift.
Fix: pin all forks to immutable tags/revisions; commit `Package.resolved`; add a CI resolution check.
Effort: S | Regression risk: medium (pin versions may differ subtly from branch HEADs — test after pinning) | Quick-fix candidate: no
Verification: clean machine resolves byte-identical revisions; `git ls-files` includes the lockfile.

### P2

**F-19 — User prompt sent to the model twice per turn** | P2 | Confidence: high (verified in source) | Category: correctness
Evidence: `ConversationStore.swift:198-199` attaches `userMessage` to the conversation (SwiftData updates the inverse `messages` in memory), then `:202-218` maps `conversation.messages` into history (now including it), then `:228-234` appends the same prompt again.
Impact: every turn duplicates the latest user message to the LLM → degraded answers, wasted tokens; analytics overcount.
Fix: build history before attaching, or drop the manual append.
Effort: XS | Regression risk: low | Quick-fix candidate: no (verify SwiftData inverse timing in a test first)
Verification: inspect outgoing `messages` — exactly one trailing user message; multi-turn ordering test.

**F-20 — Send-setup errors swallowed → UI stuck in `.loading`** | P2 | Confidence: high | Category: correctness
Evidence: `ConversationStore.swift:241-246` — `Task { try await … }` discards errors; `conversationState = .loading` set at :239; `handleError` only reachable inside the inner generation task.
Impact: any SwiftData failure during send leaves an eternal spinner with no error and no recovery besides a new prompt.
Fix: `do/catch` → `handleError` on MainActor.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: throwing service stub → state becomes `.error`.

**F-21 — Think-cache fields are persisted, storing content 2–3×** | P2 | Confidence: high | Category: persistence
Evidence: `MessageSD.swift:17-21` — five cache properties (`cachedThink`, `cachedHasThink`, `cachedThinkComplete`, `cachedRealContent`, `lastContentScan`) lack `@Transient`; `@Model` persists them; `lastContentScan` mirrors full content.
Impact: ~2–3× storage for all history and pointless writes per save.
Fix: mark all five `@Transient` — **note: schema-touching; batch with F-03 discipline** (lightweight migration handles transient marking, but verify against a fixture store first).
Effort: XS | Regression risk: low-medium | Quick-fix candidate: no (persistence rule)
Verification: store size drops; think/realContent parsing tests unchanged.

**F-22 — Conflicting delete rules on Conversation↔Model** | P2 | Confidence: medium | Category: persistence
Evidence: `ConversationSD.swift:18-19` `.nullify` on `model`; `LanguageModelSD.swift:18-19` `.cascade` on the inverse — declared on both sides with different rules (verified in source).
Impact: depending on which rule wins (can vary by OS release), "delete all models" from Settings either nulls safely or **cascade-deletes every conversation**.
Fix: declare one side only; choose `.nullify`.
Effort: XS | Regression risk: medium | Quick-fix candidate: no
Verification: test — delete model, conversations survive with `model == nil`.

**F-23 — `generationTask` assigned off-MainActor, read on main — rapid-send race** | P2 | Confidence: medium | Category: correctness
Evidence: `ConversationStore.swift:267` assigns inside the outer unstructured task (`:241`, not MainActor-isolated); `stopGenerate`/`resetStreamingState` read/cancel on MainActor. Two quick sends can leave the first stream untracked.
Impact: concurrent streams appending to `messages.last` (garbled text); Stop can't cancel orphans.
Fix: assign on MainActor; guard mutations with a generation-ID token.
Effort: S | Regression risk: medium | Quick-fix candidate: no
Verification: rapid-fire sends in a test → exactly one active stream.

**F-24 — `reloadConversation` publishes via `DispatchQueue.main.async` — leading tokens can be dropped** | P2 | Confidence: medium | Category: correctness
Evidence: `ConversationStore.swift:101-111` queues the `messages` assignment and returns; `sendPrompt:245` proceeds; `handleReceive` early-returns when `messages.isEmpty`.
Impact: fast-responding local providers can deliver tokens before the queued assignment runs → silent loss of the start of the answer; timing-dependent.
Fix: assign synchronously on MainActor before continuing.
Effort: XS | Regression risk: low | Quick-fix candidate: no (timing-sensitive; needs a test)
Verification: instrument first-token vs assignment ordering with an instant mock provider.

**F-25 — `CompletionsStore` mutates observable state off-main** | P2 | Confidence: high | Category: correctness
Evidence: `CompletionsStore.swift:11-50` — non-`@MainActor` class, `nonisolated(unsafe) shared`; `load()` sets `completions` inside `withAnimation` from an arbitrary executor; `init` calls `load()`.
Impact: Observation publishes off-main → "Modifying state during view update" class issues.
Fix: `@MainActor` the class (or hop for the mutation).
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: Main Thread Checker clean at launch.

**F-26 — Apple Foundation provider discards conversation history** | P2 | Confidence: high (verified in source) | Category: correctness
Evidence: `AppleFoundationService.swift:86-87` — `actualPrompt = lastUserMessage?.content ?? prompt`; the formatted multi-turn `prompt` is only a fallback; a fresh session per request (:57).
Impact: multi-turn chat with the Apple provider is stateless; system prompts ignored.
Fix: send the full formatted prompt (or keep a per-conversation session).
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: two-turn conversation referencing turn one; reply uses prior context.

**F-27 — Swama SSE parser: byte-by-byte O(n²) + destructive 1MB clamp** | P2 | Confidence: high | Category: correctness/performance
Evidence: `SwamaService.swift:193-248` — per-byte async iteration; `firstIndex(of: 10)` rescans from buffer start per byte; `>1MB` → `buffer.removeAll()` mid-line (corrupts the in-flight event; decode failure only logged).
Impact: quadratic parse time on long lines; silent content loss past 1MB; needless CPU at high token rates.
Fix: `URLSession.AsyncBytes.lines` or chunked splitting with a cursor; treat oversize lines as errors.
Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: mock SSE server with >1MB line + many tiny lines; assert no loss and linear time.

**F-28 — Blanket `NSAllowsArbitraryLoads`** | P2 | Confidence: high | Category: app-store/security
Evidence: `Info.plist:7-11`; docs claim "localhost only" (`PRE_SUBMISSION_CHECKLIST.md:140`) while the app connects to arbitrary user-supplied URLs, auto-prefixing `http://` (`OllamaService.swift:41-43`, `SwamaService.swift:48-50`).
Impact: plaintext HTTP (potentially bearing bearer tokens, F-09) to any host; Apple asks for justification on review; docs/binary mismatch.
Fix: scope to `NSAllowsLocalNetworking` (Apple's recommended narrow exception for local servers) or `NSExceptionDomains` for localhost/.local; warn on non-loopback HTTP with a token.
Effort: S | Regression risk: medium (could break remote-HTTP users) | Quick-fix candidate: no
Verification: `plutil -p` archived Info.plist; HTTP to `192.168.x.x` and localhost behave per chosen policy.

**F-29 — Signed `Molten.app` committed to git, stale and mismatched** | P2 | Confidence: high | Category: security/hygiene
Evidence: 29 tracked files under `Molten.app/` incl. executable + `_CodeSignature`; binary metadata `com.ondemandworld.Molten` / `1.0.0` / build `3` vs current `com.ondemandworld.molten` / `1.0.1` / `4`.
Impact: supply-chain ambiguity (which binary did users run?), repo bloat, stale config misread as current, proof that version drift already happened.
Fix: `git rm -r --cached Molten.app`; gitignore `*.app/`; purge history if public; release via App Store/tags only.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: `git ls-files | grep Molten.app` empty; fresh clone builds.

**F-30 — Speech recognition not forced on-device — voice may leave the device** | P2 | Confidence: medium | Category: privacy
Evidence: `SpeechRecogniser.swift:143-144` never sets `requiresOnDeviceRecognition` (grep: 0 hits); `SFSpeechRecognizer` falls back to Apple's network recognition when on-device is unavailable. PRIVACY.md: "never leave your Mac".
Impact: dictated audio (potentially sensitive) can be transmitted to Apple — conflicts with marketing and must be reflected in App Privacy labels if retained.
Fix: `requiresOnDeviceRecognition = true` when `supportsOnDeviceRecognition`, with an explicit fallback notice; otherwise disclose in privacy policy/labels.
Effort: S | Regression risk: medium (some hardware loses the feature if forced) | Quick-fix candidate: no
Verification: airplane mode → recognition still works; or breakpoint on `supportsOnDeviceRecognition`.

**F-31 — Touch targets 12–22pt across the chat UI** | P2 | Confidence: high | Category: ui-a11y
Evidence: stop button `.frame(width: 12)` (`ChatView_iOS.swift:170`), send 18 (:173), photo icon height 19 (:127), header icons width 22 with no padding (:94,:114), mic 20×20 (`RecordingView.swift:52`), history rows ~20pt.
Impact: mis-taps on send/stop during streaming; below HIG minimums.
Fix: 44×44pt hit areas via `contentShape` + padding (visuals unchanged); pad rows ≥44pt.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: View Debugger hit rects ≥44pt.

**F-32 — No Reduce Motion support; infinite animations** | P2 | Confidence: high | Category: ui-a11y
Evidence: 0 `accessibilityReduceMotion` references; `repeatForever` animations in `RunningBorder.swift:25`, `View+Extension.swift:96,144`, `symbolEffect(.repeat(100))` in `ReadingAloudView.swift:18`.
Impact: perpetual motion for Reduce Motion users; vestibular risk.
Fix: gate looping effects on `@Environment(\.accessibilityReduceMotion)`.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: Reduce Motion on → no looping animations.

**F-33 — Dark-mode-breaking hardcoded colors + XR color warning** | P2 | Confidence: high | Category: ui-a11y
Evidence: `ChatMessageView.swift:68-70` pure-black "thinking" bar on dark bg (0x18191d); `UnreachableAPIView.swift:30-37` black pill button; actool warning on `bgCustom.colorset` referencing an XR-only `systemBackgroundColor`.
Impact: invisible affordances in dark mode; color may render wrong on some platforms.
Fix: semantic colors (`Color(.label)`, `.secondarySystemFill`, materials); fix the colorset's platform declarations.
Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: toggle dark mode; inspect think block + unreachable banner; warning gone.

**F-34 — No localization infrastructure; hand-rolled plurals** | P2 | Confidence: high | Category: ui-a11y
Evidence: no `.strings`/`.xcstrings`; zero `NSLocalizedString`/`String(localized:)`; hardcoded strings throughout (e.g., `ChatMessageView.swift:82-84`, `UnreachableAPIView.swift:17`, `SettingsView.swift:243`); `Date+Extension.swift:20-27` hand-writes "1 day ago"/"N days ago".
Impact: future localization is a full retrofit; plurals wrong for most locales.
Fix: `String(localized:)` + String Catalog; `Date.RelativeFormatStyle`.
Effort: M | Regression risk: low | Quick-fix candidate: no
Verification: pseudo-localization build (`-accentedLocalizedStrings`).

**F-35 — Error UX: raw `localizedDescription`, no retry/dismiss** | P2 | Confidence: high | Category: ui-a11y
Evidence: `handleError(error.localizedDescription)` (`ConversationStore.swift:300`); `ConversationStatusView.swift:17-22` red text only, persists until next send; speech errors injected into the transcript as text (`SpeechRecogniser.swift:193-195`).
Impact: users see Apple boilerplate with no recovery path; dead-end when the server drops mid-stream.
Fix: map provider errors to friendly messages + Retry (keep last prompt); accessibility announcement.
Effort: M | Regression risk: low | Quick-fix candidate: no
Verification: kill server mid-stream; verify message + retry.

**F-36 — Message image re-decoded on every body evaluation** | P2 | Confidence: high (scale requires measurement) | Category: performance
Evidence: `ChatMessageView.swift:29-31` runs `Image(data:)` (→ `UIImage(data:)`) inside `body`.
Impact: repeated JPEG decodes during streaming re-renders of the same row.
Fix: decode once into `@State` on appear/task.
Effort: S | Regression risk: low | Quick-fix candidate: **yes** (verify via measurement)
Verification: Instruments — count decode calls during streaming.

**F-37 — Full-list swap invalidation hack** | P2 | Confidence: high | Category: performance
Evidence: `ConversationStore.swift:158-161, 368-371` — `messages = []; messages = currentMessages` ("Force SwiftUI to see the change").
Impact: whole-list diff/re-render at completion; symptom of fighting observation.
Fix: mutate `@Model` fields and rely on row observation; remove the swap.
Effort: S | Regression risk: medium | Quick-fix candidate: no
Verification: SwiftUI Instruments body counts on completion.

**F-38 — Animated scroll-to-bottom on every streamed chunk** | P2 | Confidence: medium | Category: performance
Evidence: `MessageListVIew.swift:120-126` — `withAnimation { scrollTo }` on each content-length change during streaming, plus two more animated scrolls per message lifecycle.
Impact: continuous animation transactions; contributes to reported freeze symptoms.
Fix: scroll without animation during streaming; skip when user has scrolled up.
Effort: S | Regression risk: low | Quick-fix candidate: **yes** (verify via measurement)
Verification: Animation Hitches template while streaming.

**F-39 — Polling ignores scenePhase; ping-interval setting never applies** | P2 | Confidence: high | Category: performance/correctness
Evidence: 0 `scenePhase` references repo-wide; timer created once in `AppStore.init` (`AppStore.swift:47-64`); `pingInterval` read only at init — Settings writes (`Settings.swift:25`) take effect only after relaunch; `save()` doesn't restart the timer.
Impact: polling never pauses in background (energy); the Settings control is functionally broken.
Fix: observe `scenePhase` (stop in `.background`, resume on `.active`); `AppStore.applyPingInterval()` from Settings save.
Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: change interval → cadence changes without relaunch; background → timer invalidated.

### P3

**F-40 — Response extraction via `Mirror` reflection** | P3 | Confidence: medium (verified in source) | Category: correctness
Evidence: `AppleFoundationService.swift:99-107` scans Mirror children for `"text"|"content"|"value"|"result"`, falling back to `String(describing: result)` — which would surface a debug description as the answer if labels change.
Fix: use the typed API (`response.content`). Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: normal text output; compile-time safety restored.

**F-41 — SSE spec edge cases unhandled** | P3 | Confidence: medium | Category: networking
Evidence: `SwamaService.swift:224,227` matches only `"data: "` (trailing space) and exact `"[DONE]"`; no multi-line `data:` accumulation; comments/`event:`/`id:` skipped without dispatch.
Fix: trim after `":"` split; accumulate `data:` fragments until blank line; trim `[DONE]`. Effort: S | Regression risk: low | Quick-fix candidate: no
Verification: mock server with `data:{…}` and split lines.

**F-42 — No request timeouts on Swama calls (and Ollama chat)** | P3 | Confidence: high | Category: networking
Evidence: `SwamaService.swift:74-91,136-171,260-285` never set `timeoutInterval` (only `reachable()` does); 60s URLSession default applies.
Fix: explicit connect/resource timeouts. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: black-hole port fails within configured timeout.

**F-43 — Day-delete predicate matches an exact instant** | P3 | Confidence: high | Category: persistence
Evidence: `SwiftDataService.swift:113-116` — `createdAt >= date && createdAt <= date` (sub-second equality); zero callers today (masked by F-01).
Fix: day-interval predicate computed by caller; `saveChanges()`. Effort: XS | Regression risk: low | Quick-fix candidate: yes (paired with F-01)
Verification: three-day fixture; delete one; exact survivors.

**F-44 — Ollama bearer-token parameter shadowed; default-localhost path drops token** | P3 | Confidence: high | Category: correctness
Evidence: `OllamaService.swift:30-32` — parameter immediately shadowed by UserDefaults read; `:55` fallback `OllamaKit(baseURL:)` for default localhost constructed **without** the stored token; Settings passes the token (`Settings.swift:58,70`) to no effect.
Fix: honor the parameter; pass token on the localhost path. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: token-only config authenticates.

**F-45 — `CancellableHolder` mutated across threads unsynchronized** | P3 | Confidence: medium | Category: correctness
Evidence: `OllamaService.swift:14-16,169,175-177,209-211` — `@unchecked Sendable` box written on caller thread, reassigned on Combine scheduler, read in `onTermination`.
Fix: lock-guard or confine to one executor. Effort: S | Regression risk: low | Quick-fix candidate: no
Verification: TSan with immediate cancellation.

**F-46 — AppStore backoff/cache state unsynchronized** | P3 | Confidence: medium | Category: correctness
Evidence: `AppStore.swift:40-45` plain vars mutated from multiple tasks; pairs with F-06.
Fix: actor-ify polling state or confine to one serial task. Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: TSan while toggling manual checks during polling.

**F-47 — Mid-stream kill loses content; `done=false` rows render as loading forever** | P3 | Confidence: high | Category: persistence
Evidence: autosave off; content persisted only at `handleComplete`/`handleError`; assistant row created `done=false` (`ConversationStore.swift:244`); force-quit mid-stream leaves it so.
Fix: throttled periodic persist; on launch sanitize stale `done=false` non-error rows. Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: kill mid-stream; relaunch shows finite state.

**F-48 — Hardcoded default token literal in source** | P3 | Confidence: high | Category: security
Evidence: `OllamaService.swift:30` default parameter is a hardcoded token-like literal (value not reproduced here); inert at runtime (shadowed, see F-44) but present in public source.
Fix: `= nil`; rotate if it's a real credential. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: grep shows `= nil`.

**F-49 — `Accessibility.plist` ships template placeholders** | P3 | Confidence: high | Category: app-store
Evidence: `Accessibility.plist:5-10` — "A description of your app's accessibility features", "subj.Molten", references a nonexistent `.accessibilitybundle`; bundled via pbxproj resource phase.
Fix: write a real description or remove the file + reference. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: archived bundle has no placeholder strings.

**F-50 — No `ITSAppUsesNonExemptEncryption`** | P3 | Confidence: high | Category: app-store
Evidence: no `NonExemptEncryption` key anywhere.
Fix: add declaration (expected `false`) — **manual verification required** with compliance owner. Effort: XS | Regression risk: low | Quick-fix candidate: **yes** (after sign-off)
Verification: next upload shows no encryption prompt.

**F-51 — No CI; release script hardcodes the version** | P3 | Confidence: high | Category: app-store/build
Evidence: no `.github/`; `scripts/release.sh` hardcodes `v1.0.1` (lines 3,8,24,44,65,89), `git add .` + tag + push with no build/test/archive/notarize steps.
Fix: GitHub Actions: resolve → build Debug+Release → test → privacy-manifest check → fail on warnings; version via argument/`agvtool`. Effort: M | Regression risk: low | Quick-fix candidate: no
Verification: PR triggers a green pipeline.

**F-52 — ChatView_iOS keyboard/focus quirks** | P3 | Confidence: medium | Category: ui-a11y
Evidence: no-op `onChange(of: isFocusedInput)` (`ChatView_iOS.swift:153-157`); whole-input-row tap gesture competing with child buttons (:176-180); no `.scrollDismissesKeyboard`; `resignFirstResponder` sendAction hack (`Chat.swift:92`).
Fix: remove no-op; scope tap gesture to the field background; add interactive scroll-dismiss. Effort: S | Regression risk: medium | Quick-fix candidate: **yes** (tap-test after)
Verification: tap-test every control; drag-to-dismiss on device.

**F-53 — iPad treated as large iPhone** | P3 | Confidence: high | Category: ui-a11y
Evidence: offset-based 300pt drawer for all non-macOS (`Chat.swift:149-157`, `SideBarMenuView.swift:10-22`); `horizontalSizeClass` consulted exactly once (`AnalyticsFooterView.swift:24-32`).
Fix: `NavigationSplitView` at regular width (incremental, size-class gated). Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: iPad Split View ⅓ width.

**F-54 — Legacy `EnchantedApp.swift` duplicate `@main` landmine** | P3 | Confidence: high (unreachability proven) | Category: architecture
Evidence: declares `@main struct MoltenApp` (same as the live entry point); pbxproj references = 0; contains stale `.onKeyboardShortcut` + `print("heya")`.
Fix: delete (or move outside the source tree). Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: `grep @main` → one result; build unaffected.

**F-55 — Four files outside the target, one uncompilable** | P3 | Confidence: high (pbxproj refs = 0) | Category: architecture
Evidence: `Header.swift` references undefined `selectedModel:25` (cannot compile); `Sidebar_macOS.swift`, `NSClipboardItem.swift` zero references; plus `EnchantedApp.swift` (F-54).
Fix: delete/archive outside the tree. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: build clean; no usage regressions.

**F-56 — Compiled-but-unreachable code** | P3 | Confidence: high (grep-verified) | Category: architecture
Evidence: Voice flow (`Voice.swift`, `VoiceView.swift` — `appState` never becomes `.voice`); zero-caller helpers (`sleepTest`, `DeallocPrinter`, `HotKeys`, `Binding.onChange`, `MovingGradientForegroundStyle`, `MoltenAnimatedStyle`); `#if false` MenuBarExtra (`MoltenApp.swift:59-71`); commented blocks (`Accessibility.swift:90-134`, `EmptyConversaitonView.swift:45-56`, `SpeechRecogniser.swift:8,222`); duplicate slash-strip (`Settings.swift:44-52`).
Fix: delete; track re-enablement in issues/history. Effort: S | Regression risk: low | Quick-fix candidate: **yes**
Verification: grep confirms no callers; build warnings unchanged.

**F-57 — Filename/type typos** | Observation-grade P3 | Confidence: high | Category: architecture
Evidence: `MessageListVIew.swift` (type `MessageListView`), `EmptyConversaitonView.swift` (typo propagated into the type name, used at three call sites).
Fix: rename files + type. Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: build; old names grep → 0.

**F-58 — Chat logic duplicated across iOS/macOS variants** | P3 | Confidence: high | Category: architecture
Evidence: `ChatView_iOS.swift` vs `ChatView_macOS.swift` + `InputFields_macOS.swift` duplicate header, image selection, edit-message handling, send/stop switching — already drifted (iOS lacks copy-chat).
Fix: extract shared header/input subviews incrementally. Effort: M | Regression risk: medium | Quick-fix candidate: no
Verification: both platforms exercised after extraction.

**F-59 — Profanity/debug prints in shipped source** | P3 | Confidence: high | Category: architecture/privacy
Evidence: `SpeechRecogniser.swift:62-65` `"denicd"`, `"wtf"`; `EnchantedApp.swift:30` `"heya"`.
Fix: delete (subsumed by F-12's logging cleanup). Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: grep → 0.

**F-60 — Settings polls the system voice list every 5 seconds** | P3 | Confidence: high | Category: performance
Evidence: `Settings.swift:38` `Timer.publish(every: 5).autoconnect()` → `fetchVoices()` sorting the full voice list each tick.
Fix: fetch once on appear (+ language-change notification). Effort: XS | Regression risk: low | Quick-fix candidate: **yes**
Verification: profiler shows no 5s recurring work while Settings open.

### Observations

- **O-01** — Chat hardcodes `temperature: 0.0` (`ConversationStore.swift:279`); the per-instruction temperature UI (`UpsertCompletionView.swift:96`) is honored only by the macOS panel VM → the setting misleads users. Fix: thread optional temperature through `sendPrompt`. Effort: S.
- **O-02** — Default-model setting never persists: `Chat.swift:16` reads `defaultSwamaModel` (never written); `Settings.swift:22` writes `defaultModel` (only its own `onChange` reads it) — verified. One key, persisted in Settings, read at launch. Effort: XS.
- **O-03** — Swama image-support heuristic (`SwamaService.swift:95-101`) matches text-only Qwen/Gemma names → UI offers image upload to models that reject it. Fail safe to `false` or query capabilities.
- **O-04** — HTTP error responses discard server bodies (`SwamaService.swift:181-185` etc.) → opaque "HTTP 400" errors where the server explains the problem; no retry on transient failures.
- **O-05** — Edit-trim semantics (`ConversationStore.swift:185-189`, `RangeReplaceableCollection.prefix(while:)` — compiles fine) silently delete later messages on edit; intentional-looking but unguarded and untested. Needs a test, not a rewrite. *(Sub-agent's "type error" suspicion on this line was checked and is a false positive.)*
- **O-06** — Connection status color-only (`SettingsView.swift:119-153`) and a 6pt selection dot in history rows; add symbols. Quick fix.
- **O-07** — Unbounded fetches (`SwiftDataService` has no `fetchLimit`) and sidebar grouping recomputed per body eval — measure with 2k conversations before acting.
- **O-08** — Entitlement duplication: empty release file vs generated `ENABLE_*` keys; inert `com.apple.security.network.client` in Info.plist. Cosmetic; final signed entitlements verified correct and minimal.
- **O-09** — Zero `#if DEBUG` anywhere → no configuration-aware code structure; release binaries behave like debug re: logging (see F-12).
- **O-10** — Concurrency-hygiene debt: `@unchecked Sendable` + `DispatchQueue.main.async` state mutation, `nonisolated(unsafe) static let shared`, actor/`ObservableObject` hybrid `SpeechRecogniser`. Manageable now; raises Swift 6 migration cost.
- **O-11** — README inaccuracies: deployment targets stated as macOS 14/iOS 17 (actual: 26.0), `xcodebuild test` instruction (no tests exist), "Mac-first" positioning vs iOS-first App Store reality.
- **O-12** — iOS/macOS 26.0 minimums exclude all pre-26 devices — a deliberate market tradeoff to reconfirm before each release.

---

## 10. Safe quick-fix candidates

All are clearly correct, small, isolated, behavior-preserving (except where correcting an obvious defect), low-regression, compatible with existing users/data, and verifiable. **None should be implemented until you approve.**

| Priority | ID | Fix | Effort | Verification |
|---|---|---|---|---|
| 1 | F-01+F-43 | Day-ranged delete predicate; call it from `deleteDailyConversations` | XS | 2-day fixture test + manual day-delete |
| 2 | F-05 | `continuation.onTermination` cancels producer tasks (Swama, Apple) | XS | cancel → byte loop exits; no orphans |
| 3 | F-12 (+F-59) | Delete body/prompt logging; DEBUG-gate the rest | S | Release `log stream` shows no content |
| 4 | F-10 | Add `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, tracking=false) | XS | Organizer privacy report; upload checks |
| 5 | F-11 | Add `INFOPLIST_KEY_NSLocalNetworkUsageDescription` (iOS) | XS | Physical-device LAN prompt test |
| 6 | F-13 | Accessibility labels/hints on all icon-only controls | S | VoiceOver walk-through |
| 7 | F-20 | `do/catch` → `handleError` for send setup | XS | throwing stub → `.error` state |
| 8 | F-25 | `@MainActor` `CompletionsStore` mutations | XS | Main Thread Checker clean |
| 9 | F-26 | Send full formatted history to Apple provider | S | two-turn context test |
| 10 | F-31 | 44pt hit areas | S | View Debugger rects |
| 11 | F-32 | Reduce Motion gating | S | Reduce Motion on → static |
| 12 | F-33 | Semantic dark-mode colors + colorset fix | XS | dark-mode pass; warning gone |
| 13 | F-36/F-38 | Decode image once; non-animated stream scroll | S | Instruments (measurement) |
| 14 | F-39 | scenePhase-aware timer; apply ping interval on save | S | interval change applies live |
| 15 | F-29 | `git rm --cached Molten.app` + gitignore | S | clean clone |
| 16 | F-44/F-48 | Honor token param; drop hardcoded literal | XS | token-only auth works |
| 17 | F-42 | Explicit request timeouts | XS | black-hole port test |
| 18 | F-49/F-50 | Fix/remove placeholder plist; encryption declaration (after compliance sign-off) | XS | archive inspection |
| 19 | F-54/F-55/F-56/F-57 | Delete proven-dead files/code; rename typos | S | build + greps |
| 20 | F-60 | Voice list fetched once | XS | profiler |

**Not quick fixes** (deliberately excluded): F-02 (dependency pins), F-03/F-04/F-21/F-22 (persistence-touching), F-09 (Keychain migration), F-14 (layout reflow), F-15/F-16/F-17 (larger efforts), F-28 (policy decision with user impact).

---

## 11. Issues requiring reproduction or measurement

| ID | What to reproduce/measure | Method |
|---|---|---|
| F-11 | Does iOS actually deny LAN connections without the usage description on current OS versions? | Fresh install on physical iPhone; Ollama on Mac LAN IP; observe prompt/failure. |
| F-08 | Trap behavior of `LanguageModelSession()` on unsupported hardware/region | Unsupported Mac config or simulator; break on poll. |
| F-06 | Timer-death after backoff; duplicate-timer windows | Stop server, wait through ≥3 failures, restart server; watch `isReachable` + timer count. |
| F-04 | Upsert relationship wipe in practice | Loop `loadModels()` against a live store; inspect `conversation.model`. |
| F-07 | Actual race occurrence | TSan build over a streaming session with stop/start churn. |
| F-19 | Double-send under real SwiftData inverse timing | Log outgoing `ChatCompletionRequest.messages` on device. |
| F-24 | First-token vs assignment ordering | Instant mock provider; instrument. |
| F-15/F-37/F-38 | Render/animation costs | Instruments SwiftUI + Animation Hitches templates, 500-message conversation. |
| F-16 | Main-thread stall magnitude | Time Profiler, 20-image conversation send. |
| F-27 | Parse throughput and >1MB loss | Mock SSE fixtures; measure. |
| F-39 | Background energy delta | Energy gauge with app backgrounded. |
| F-03 | Migration failure modes | Fixture stores per shipped schema + corrupted-store boot test. |

---

## 12. Dependencies and build-system recommendations

Resolved set (2026-08-01; web research pass, sources in agent citations — GitHub API + Apple docs):

| Package | Pinned | Status / notes (as of 2026-08-01) |
|---|---|---|
| KeyboardShortcuts (sindresorhus) | `upToNextMajor` 2.0.0 → 2.0.1 | Active; **2.0.1 renamed the SwiftUI modifier — broke the macOS build (F-02)**. |
| swift-markdown-ui / MarkdownUI (gonzalezreal) | 2.4.1 | **Officially in maintenance mode**; successor project `textual`. Plan a medium-term migration. |
| OllamaKit — fork (gluonfield, ex-AugustDev) | branch `main` @ 0079411 | Fork; true upstream is `kevinhermawan/OllamaKit`. Branch head verified current — but floating. |
| Splash — fork (gluonfield) | branch `master` @ c31eba0 | Upstream (JohnSundell) is dormant; fork head current; floating. |
| Magnet — fork (gluonfield) + Sauce (Clipy) | branch `master` @ 4865f86; Sauce 2.4.1 | Clipy repos revived in 2026; fork head current; floating. |
| Alamofire (transitive via OllamaKit) | 5.9.1 | Current 5.12.0; no CVEs since 5.9.1; ships privacy manifest since 5.9.0 → **compliant as pinned**. |
| swift-async-algorithms (apple) | 1.0.0 | Stable/active. |
| Vortex (twostraws) | 1.0.1 | Active. |
| ActivityIndicatorView (exyte) | 1.1.1 | Active. |
| WrappingHStack (ksemianov) | 0.2.0 | Low activity; tiny surface. |
| cmark-gfm, NetworkImage, swift-collections (transitive) | 0.5.0 / 6.0.1 / 1.1.0 | Maintained transitives. |

Recommendations (each individually; none to be done during the audit):

1. **Commit `Package.resolved` and remove it from `.gitignore`** (F-18). Benefit: reproducible builds/reviews/rebuilds. Risk: none. Testing: clean-machine resolution equality.
2. **Pin the three fork branches to immutable revisions/tags** and re-verify builds. Benefit: no silent supply-chain drift. Risk: medium — pin contents may differ subtly from what produced v1.0.1; full regression pass on all three providers required.
3. **Fix F-02 (rename modifier call) and pin KeyboardShortcuts exactly.** Benefit: macOS builds again. Risk: low.
4. **Alamofire 5.9.1 → 5.12.0** only when OllamaKit's constraint allows (it's transitive). Benefit: upstream fixes; already privacy-compliant at 5.9.1, so no urgency. Risk: low; test Ollama streaming.
5. **Plan MarkdownUI successor migration** as future modernization (maintenance-mode dependency in the rendering hot path).
6. **Add CI** (F-51): resolve → build (Debug+Release, macOS+iOS) → test → privacy-manifest presence check → fail on warnings. This is what would have caught F-02 before release.
7. **Treat `actool` XR color warning (F-33) as a build-hygiene item** once CI fails on warnings.

---

## 13. Testing gaps and recommended regression suite

No tests exist (F-17). Highest-risk untested logic is mostly pure and cheap to cover. Recommended starter suite (unit target only; no UI harness needed):

1. **ContentType decode/encode** (`ModelProviderProtocol.swift:36-131`): string payload, array payload, `content: null` delta, round-trip equality.
2. **Swama SSE parser** (`SwamaService.swift:193-249`): chunk splits mid-line, `data: [DONE]`, `event:`/`id:` skips, CRLF, malformed line skipped without halting, >1MB single event (currently corrupts — F-27).
3. **MessageSD think parsing** (`MessageSD.swift:34-94`): no tag, unclosed tag mid-stream, completed tag, empty real content, cache invalidation on content change.
4. **ConversationStore analytics** (`:324-363`) with a fake `ModelProviderProtocol`: prompt/eval splits, token-estimate fallbacks, `usage` precedence. Requires provider injection (F-17/H-2 note: a minimal protocol seam, not a refactor).
5. **Edit-trim semantics** (`:185-189`): truncates at message id; document unmatched-id behavior (O-05).
6. **AppStore backoff math** (`AppStore.swift:117-143`): 30→300 cap (default localhost), 10→60 (user URL), reset on success.
7. **Day-delete predicate** (after F-01/F-43): range deletes only the target day.
8. **`Date.daysAgoString`** (`Date+Extension.swift:11-28`): 0/1/2/n days, calendar-boundary edge.
9. **Integration-style**: fake provider yielding N chunks → final `messages.last.content`, `done == true`, buffer flushed, `stopGenerate()` cancels producer (covers F-05 regression).
10. **Persistence migration fixtures**: open a v1.0.1-era store under future schemas (becomes mandatory before any schema change — F-03).

Later: UI tests for accessibility (VoiceOver-focused), and a malformed-response fuzz pass on both network providers.

---

## 14. App Store, privacy, and release checklist

| Check | Status | Action |
|---|---|---|
| Privacy manifest (app) | ❌ Missing | F-10 (quick fix) |
| Required-reason APIs declared | ❌ UserDefaults undeclared (CA92.1 fits) | F-10 |
| Third-party SDK manifests/signatures | ✅ Only Alamofire is on Apple's commonly-used list and it ships its own manifest (5.9.0+); re-check at every dependency bump | — |
| Usage descriptions: mic, speech | ✅ Present, accurate, lazy-requested | — |
| Usage description: local network (iOS) | ❌ Missing — core feature risk | F-11 (quick fix; **manual device verification**) |
| ATS | ⚠️ Blanket arbitrary loads vs "localhost-only" docs | F-28 (prefer `NSAllowsLocalNetworking`) |
| Encryption declaration | ❌ Missing | F-50 (compliance sign-off, **manual verification required**) |
| Secrets handling | ❌ Tokens in UserDefaults + visible TextField | F-09 |
| Logging privacy | ❌ Prompts/images logged in release | F-12 |
| Data-collection vs privacy labels | ⚠️ Consistent except speech recognition's possible Apple-network path | F-30; update labels/policy if path retained (**manual verification required** in App Store Connect) |
| Entitlements/sandbox | ✅ Minimal, verified in signed binary (both configs) | Optional cleanup O-08 |
| Accounts / Sign in with Apple / account deletion | N/A — no accounts | — |
| IAP / subscriptions | N/A — none | — |
| Tracking consent | N/A — no tracking (declare `NSPrivacyTracking=false` via F-10) | — |
| AI-app review posture | ⚠️ Nov-2025 rule 5.1.2(i) on AI data-sharing + June-2026 4.3(b) duplicate-app tightening are the relevant recent changes; app's local-only design is well-positioned, but privacy labels must match F-30's outcome | **manual verification required** |
| Version/build management | ⚠️ Manual; drift already evidenced (F-29) | F-51 |
| Placeholder content | ⚠️ Accessibility.plist template text (F-49); Voice feature stub visible in code (F-56, not user-visible) | Quick fixes |
| App Store Connect state (certs, labels, screenshots, review notes) | Unknown | **manual verification required** |

---

## 15. Prioritized improvement roadmap

**Before new feature development (stabilization, ~1–2 focused weeks):**
- Fix F-01/F-43 (data loss) — first, always.
- Restore reproducible builds: commit `Package.resolved`, pin forks, fix F-02.
- Compliance quick fixes: F-10, F-11, F-50 (after sign-off), F-12 log scrub.
- Stop-button correctness (F-05); stuck-spinner fix (F-20); Apple multi-turn fix (F-26).
- Stand up the unit test target + items 1–3, 7–8 of §13 (pure logic, no DI needed).

**During the next feature cycle:**
- Accessibility pass: F-13 (labels), F-14 (Dynamic Type), F-31 (targets), F-32 (Reduce Motion), F-33 (dark mode), F-35 (error UX).
- Persistence safety: F-03 (versioned schema + migration plan) before any model change; F-04 fetch-or-update; F-22 delete rules; F-21 transients (as a deliberate schema step).
- Concurrency correctness: F-06, F-07, F-23, F-24, F-46 (with TSan in CI).
- Keychain migration for tokens (F-09) + ATS scoping (F-28) together.
- Performance: F-15 lazy list, F-16 off-main encoding, F-39 scenePhase; measure per §11.
- Expand §13 suite incl. fake-provider injection seam (F-17/H-2, minimal seam only).

**Future modernization:**
- CI pipeline (F-51) — can start earlier; becomes mandatory once tests exist.
- MarkdownUI → successor migration; revisit forked deps vs upstreams.
- iPad-first layout (F-53); localization infrastructure (F-34); shared iOS/macOS components (F-58).
- Swift 6 language mode once O-10 debt is paid down.
- Observability: `os.Logger` subsystem + MetricKit (no third-party crash SDK needed for a privacy-first app).

---

## 16. Suggested implementation batches (each independently testable)

- **Batch 0 — Safety & compliance (all quick fixes; no architecture touched):** F-01+F-43, F-05, F-10, F-11, F-12+F-59, F-20, F-25, F-44+F-48, F-42, F-49, F-50, F-29, F-60. *Gate: day-delete test green; Release log clean; archive shows manifest; macOS/iOS builds unchanged in behavior.*
- **Batch 1 — Build reproducibility:** commit `Package.resolved`, pin forks to revisions, F-02 rename, exact-pin KeyboardShortcuts. *Gate: clean-machine macOS + iOS builds byte-stable resolution; full manual pass on all three providers.*
- **Batch 2 — Test foundation:** unit target + §13 items 1–3, 5–9; minimal fake-provider seam. *Gate: CI-less local `xcodebuild test` green; coverage on listed functions.*
- **Batch 3 — Accessibility & platform polish:** F-13, F-14, F-31, F-32, F-33, F-35, F-36, F-38, F-52, F-39. *Gate: VoiceOver + Dynamic Type + Reduce Motion + dark-mode manual pass on iPhone and iPad.*
- **Batch 4 — Persistence hardening (migration-planned):** F-03, F-04, F-22, F-21, F-47 + migration fixture tests. *Gate: v1.0.1-era fixture store opens and migrates; no data loss in delete/upsert tests.*
- **Batch 5 — Concurrency & secrets:** F-06, F-07, F-23, F-24, F-46, F-45 (TSan-gated) + F-09 Keychain migration + F-28 ATS scoping. *Gate: TSan clean; token migration test; HTTP policy matrix tested.*
- **Batch 6 — Performance (measurement-gated):** F-15, F-16, F-37 + §11 instrumentation. *Gate: Instruments before/after with defined thresholds.*

---

## 17. Open questions and manual checks

1. **Is macOS a shipping channel?** If the Mac app is distributed (Developer ID / Mac App Store), F-02 is a P0 release blocker today. *(The committed binary and submission docs suggest macOS distribution — manual verification required.)*
2. **App Store Connect privacy labels** — do they currently disclose speech recognition's possible network path (F-30)? Manual verification required.
3. **iOS LAN behavior without `NSLocalNetworkUsageDescription`** — confirm on a physical iPhone across iOS 26.x (F-11). If connections are denied, this is P0 for iOS.
4. **Distribution channel & sandbox expectations** — Mac App Store would require sandbox (present); Developer ID only needs hardened runtime (present). Confirm channel.
5. **Encryption exemption determination** (F-50) — legal/compliance sign-off needed before declaring `ITSAppUsesNonExemptEncryption = false`.
6. **Are the fork pins (OllamaKit/Splash/Magnet branch heads) what built v1.0.1?** Without a committed lockfile this is unknowable — verify against the archived build's framework versions if the archive is available.
7. **`LanguageModelSession()` trap behavior** on unsupported configurations (F-08) — confirm against current FoundationModels documentation/device.
8. **Temperature intent** (O-01) — is `0.0` deliberate for chat? The UI implies otherwise.
9. **Voice feature** (F-56) — ship it or remove it? Currently a dead branch that looks like a feature.
10. **Minimum OS strategy** (O-12) — confirm iOS/macOS 26.0 floor is intentional for the next version.

---

## 18. Final recommendation

**The project is conditionally ready for new feature work.** The architecture is sound enough to build on, the privacy posture is genuine, and most defects are fixable incrementally. But starting feature work before Batch 0+1 would compound two real risks: (a) a user-facing data-loss bug in a shipped feature, and (b) an unreproducible build that already breaks macOS from a clean checkout. Neither requires redesign — both are days of work. After Batches 0–2 (safety, reproducibility, minimal tests), the codebase is a responsible base for the next version; Batches 3–6 can proceed alongside feature development.

---

### The five highest-priority actions

1. **Fix F-01/F-43** — day-delete must delete a day (P0 data loss). XS.
2. **Make builds reproducible** — commit `Package.resolved`, pin forks, fix F-02 so macOS compiles (P1, demonstrated). S.
3. **Ship compliance basics** — privacy manifest (F-10), `NSLocalNetworkUsageDescription` (F-11), encryption declaration (F-50). XS each.
4. **Scrub release logging** of prompts/images (F-12) and **fix Stop** (F-05). S/XS.
5. **Create the unit test target** with the §13 starter behaviors (F-17) — every later change depends on this. S–M.

### The safest quick wins

F-01/F-43, F-05, F-10, F-11, F-12, F-20, F-25, F-26, F-33, F-42, F-44/F-48, F-49, F-60 — all XS/S, isolated, and verifiable with a build or a narrowly scoped check.

### Areas that must not change without migration/compatibility planning

- **SwiftData models and container setup** (`SwiftDataService.swift`, `SwiftData/Models/*`) — no property adds/renames/retypes before F-03's versioned schema + migration fixtures; existing users' stores must open.
- **UserDefaults keys** (`ollamaUri`, `ollamaBearerToken`, `swamaUri`, `swamaApiKey`, `pingInterval`, `systemPrompt`, `colorScheme`, `vibrations`, `appUserInitials`, `voiceIdentifier`, `defaultModel`/`defaultSwamaModel`) — renaming or retyping (note `pingInterval` is a String-parsed Double) breaks existing installs; the Keychain migration (F-09) must copy-then-delete.
- **Bundle identifier, entitlements, team, ATS scope narrowing** — any change affects signed builds and possibly existing users' remote-HTTP endpoints (F-28).
- **Dependency pins** — change deliberately with a full three-provider regression pass (Batch 1).

### Proposed prompt for implementing only the approved first batch

> Implement **Batch 0** from `IOS_TECHNICAL_AUDIT.md` on branch `audit/ios-review`, and nothing else. Rules: no dependency, deployment-target, entitlement, bundle-id, or persistence-schema changes; do not touch `SwiftData/Models/*` beyond what F-21 would require (F-21 is NOT in Batch 0); keep diffs minimal and per-finding. In scope: F-01+F-43 (day-ranged delete + correct call), F-05 (producer cancellation in SwamaService and AppleFoundationService, mirroring OllamaService's onTermination), F-10 (add `Molten/PrivacyInfo.xcprivacy` with tracking=false and UserDefaults CA92.1, wired into the target), F-11 (iOS `NSLocalNetworkUsageDescription` via INFOPLIST_KEY), F-12+F-59 (remove prompt/body/selected-text logging; DEBUG-gate or delete remaining prints), F-20 (catch setup errors → handleError), F-25 (@MainActor CompletionsStore mutations), F-44+F-48 (honor bearer-token parameter; remove the hardcoded default literal), F-42 (explicit request timeouts), F-49 (fix or remove Accessibility.plist placeholders), F-50 (add `ITSAppUsesNonExemptEncryption=false` — only if compliance sign-off is confirmed, otherwise skip and note), F-29 (`git rm -r --cached Molten.app` + gitignore `*.app/`), F-60 (fetch voices once). For each finding: cite the ID in the commit message, add or note the verification from §10, and run `xcodebuild build -sdk iphonesimulator26.5 CODE_SIGNING_ALLOWED=NO` plus the macOS build to confirm no new warnings. Stop and report before any out-of-batch change.

---

*Audit performed read-only per Phase-1 operating rules. No production source, settings, dependencies, or persistence artifacts were modified. This report (`IOS_TECHNICAL_AUDIT.md`) and the previously created `CLAUDE.md` are the only files added; neither has been committed.*
