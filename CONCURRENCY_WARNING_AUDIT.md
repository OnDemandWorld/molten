# Molten — Concurrency and Warning Audit

**Review date:** 2026-08-01 · **Mode:** read-only investigation (no production code, project, or dependency changes) · **Compiler:** Xcode 26.6 (17F113), Swift 5.0 language mode with `SWIFT_STRICT_CONCURRENCY = complete`

---

## 1. Executive summary

**Warning counts (deduplicated per clean-build log):**

| | macOS Debug | macOS Release | iOS Simulator Debug | iOS Simulator Release |
|---|---|---|---|---|
| **Baseline `af7ba46`** | 58 | 58 | 59 | 59 |
| **Current HEAD `ea84611`** | 58 | 58 | 59 | 59 |
| **Δ** | **0** | **0** | **0** | **0** |

- **Baseline vs HEAD:** the warning *set is identical*. Fingerprint diffing shows 47 fingerprints shared; the 4 "HEAD-only" and 4 "baseline-only" fingerprints are the **same four SwiftData `#Predicate` KeyPath-Sendable diagnostics** whose macro-generated filenames embed source line numbers that shifted when `SwiftDataService.swift` grew (§6). Net new warnings introduced by the stabilization tranche: **zero**; net removed: **zero**; net moved: 4 (line-shift artifacts).
- **One important baseline caveat:** the baseline worktree resolves packages *fresh* (no committed lockfile at `af7ba46`). Today that resolves **KeyboardShortcuts 2.4.0** (which again exposes `onGlobalKeyboardShortcut`) plus newer transitives (Alamofire 5.12.0, ActivityIndicatorView 1.2.1, Vortex 1.0.4, async-algorithms 1.1.5, collections 1.6.0, cmark 0.8.0), so the baseline macOS build — which failed at audit time against 2.0.1 — now succeeds. This is a live demonstration of the drift the committed lockfile (F-02/F-18) stops; the warning comparison is valid but the baseline's *dependency set differs* from the audited one (§4).
- **Swift 6 errors-in-waiting:** **46 warning occurrences per macOS configuration, 43 per iOS configuration** (identical baseline vs HEAD). If `SWIFT_VERSION` were set to 6 today, these would be hard errors. The 9 SwiftData KeyPath-Sendable diagnostics among them *appear to be SwiftData/toolchain diagnostics for which no safe application-level fix has been identified yet* — but this should be re-measured after the main-context refactor and a Swift 6 spike before being declared permanent toolchain blockers (§12, §14).
- **Highest-risk categories:** (1) live `PersistentModel` instances crossing the `SwiftDataService` actor boundary and then being mutated on the MainActor — ~25 diagnostics and a genuine data race (audit F-07); (2) unstructured `Task`/`Timer`/`DispatchQueue` isolation in the four stores — ~28 diagnostics, including the reachability-timer death bug (F-06); (3) SwiftData `#Predicate`/`SortDescriptor` KeyPath-Sendable diagnostics — Apple toolchain gap, blocks Swift 6 mode, unfixable in app code.
- **Recommended SwiftData ownership model:** **Option A — main-actor ownership.** One `ModelContainer` created at the app root; the `@MainActor` `mainContext` is the only context touching live models; stores become `@MainActor`; provider services return Sendable DTOs (already nearly true); persistence saves happen on the main context. Zero data-migration risk (same store file and schema), aligned with Apple's SwiftUI+SwiftData design, and it eliminates the large majority of errors-in-waiting (§10).

---

## 2. Environment and methodology

- **Host:** Apple Silicon Mac; **Xcode 26.6** (build 17F113); SDKs iOS 26.5 / macOS 26.5; iOS Simulator runtimes 18.2–26.5; destination used: `platform=iOS Simulator,name=iPhone 17,OS=26.5` (discovered via `-showdestinations`).
- **Build settings (both configs):** `SWIFT_VERSION = 5.0`; `SWIFT_STRICT_CONCURRENCY = complete`; `SWIFT_TREAT_WARNINGS_AS_ERRORS` absent (NO); `GCC_TREAT_WARNINGS_AS_ERRORS = NO`; **no** `SWIFT_DEFAULT_ACTOR_ISOLATION` and **no** `SWIFT_UPCOMING_FEATURE_*` flags (defaults: nonisolated-by-default, Swift 5 inference rules); Release uses `SWIFT_COMPILATION_MODE = wholemodule`, Debug `-Onone` + `DEBUG` condition.
- **Method:** temporary git worktree at `/tmp/molten-warning-baseline` (detached HEAD `af7ba46`; user's working tree untouched on `audit/ios-review`). Eight **clean** builds — fresh DerivedData per checkout (`/tmp/dd-base`, `/tmp/dd-head`), Debug+Release × macOS+iOS Simulator for both checkouts, identical flags (`CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`), raw logs kept at `/tmp/wb_*.log`. Warnings extracted by regex, deduplicated per log, paths normalized (repo prefixes → `REPO/`, DerivedData DerivedSources → `<generated>/`, SPM checkouts → `<dep:…>/`), fingerprinted by (origin, normalized path, exact text), and set-compared across baseline/HEAD. Each macro-generated diagnostic was traced to its originating source expression via the compiler's "in expansion of macro" notes — **not** classified by filename alone.
- **Limitations:** builds unsigned (no entitlement inspection); warning *line* numbers are stable only within a checkout — cross-checkout comparison uses text fingerprints; the baseline's floating dependencies resolved to today's branch heads (recorded in §4).

---

## 3. Build matrix

| # | Checkout | Platform | Config | Destination | Result | Log |
|---|---|---|---|---|---|---|
| 1 | baseline `af7ba46` | macOS | Debug | `platform=macOS` | **BUILD SUCCEEDED** ¹ | `/tmp/wb_base_mac_dbg.log` |
| 2 | baseline `af7ba46` | macOS | Release | `platform=macOS` | **BUILD SUCCEEDED** ¹ | `/tmp/wb_base_mac_rel.log` |
| 3 | baseline `af7ba46` | iOS Simulator | Debug | iPhone 17 / 26.5 | **BUILD SUCCEEDED** | `/tmp/wb_base_ios_dbg.log` |
| 4 | baseline `af7ba46` | iOS Simulator | Release | iPhone 17 / 26.5 | **BUILD SUCCEEDED** | `/tmp/wb_base_ios_rel.log` |
| 5 | HEAD `ea84611` | macOS | Debug | `platform=macOS` | **BUILD SUCCEEDED** | `/tmp/wb_head_mac_dbg.log` |
| 6 | HEAD `ea84611` | macOS | Release | `platform=macOS` | **BUILD SUCCEEDED** | `/tmp/wb_head_mac_rel.log` |
| 7 | HEAD `ea84611` | iOS Simulator | Debug | iPhone 17 / 26.5 | **BUILD SUCCEEDED** | `/tmp/wb_head_ios_dbg.log` |
| 8 | HEAD `ea84611` | iOS Simulator | Release | iPhone 17 / 26.5 | **BUILD SUCCEEDED** | `/tmp/wb_head_ios_rel.log` |

¹ **Baseline macOS succeeded only because of dependency drift:** fresh resolution pulled KeyboardShortcuts **2.4.0** (vs 2.0.1 at audit time, which removed `onGlobalKeyboardShortcut` and broke this build — finding F-02). Neither checkout was edited to make a build pass; the comparison is valid for warnings but the baseline dependency set is not the audited set (§4). All eight are *complete* builds (through linking and asset catalogs), not Swift-only.

---

## 4. Baseline comparison

**Per-log deduplicated counts:** baseline 58/58/59/59 vs HEAD 58/58/59/59 (macOS Dbg/Rel, iOS Dbg/Rel). **Fingerprints:** 55 total — 47 shared, 4 HEAD-only, 4 baseline-only.

| Warning fingerprint | Baseline | Current | Classification | Source |
|---|---|---|---|---|
| 46 project-source concurrency/deprecation diagnostics (ConversationStore ×17, SwiftDataService ×9, CompletionsStore ×7, AppStore ×6, Binding+Extension ×3, Chat ×2, PanelManager ×2, LanguageModelStore ×2, Accessibility ×2, OllamaService ×1, RecordingView ×1, SplashSyntaxHighlighter ×1, PromptPanelView ×1; + iOS-only HapticsService ×4, SpeechRecogniser ×1) | ✓ (same texts; line numbers differ where files changed) | ✓ | **pre-existing** | project source |
| 4 SwiftData `#Predicate` macro KeyPath-Sendable diagnostics (KeyPath<ConversationSD, UUID> — `getConversation`; KeyPath<ConversationSD, Date> ×2 — day-delete predicate; KeyPath<MessageSD, Optional<ConversationSD>> + KeyPath<ConversationSD, UUID> — message-by-conversation predicate) | ✓ as `…MX96…`, `…MX113…`, `…MX122…` | ✓ as `…MX99…`, `…MX122…`, `…MX132…` | **moved (line-shift of generated filenames), same diagnostics** — see §6 trace | generated macro source → `SwiftDataService.swift:100,123,133` |
| `GeneratedAssetSymbols.swift`: `"label"` color asset resolves to conflicting `UIColor` symbol | ✓ (iOS only) | ✓ (iOS only) | pre-existing | generated source |
| 2 actool warnings: `bgCustom.colorset` references XR `systemBackgroundColor` | ✓ | ✓ | pre-existing | asset catalog |
| `xcodebuild: WARNING: Using the first of multiple matching destinations` | ✓ | ✓ | pre-existing, benign | build tool |
| dependency-sourced warnings | none | none | — | dependencies |

**Baseline dependency resolution (today, fresh, no lockfile) vs HEAD (committed lockfile):**

| Package | Baseline resolved (2026-08-01 fresh) | HEAD pinned | Drifted? |
|---|---|---|---|
| KeyboardShortcuts | **2.4.0** (`1aef8557…`) | **2.0.1** (`2e5f1558…`, exactVersion) | yes — baseline floated forward |
| Alamofire | **5.12.0** | 5.9.1 | yes |
| ActivityIndicatorView | **1.2.1** | 1.1.1 | yes |
| Vortex | **1.0.4** | 1.0.1 | yes |
| swift-async-algorithms | **1.1.5** | 1.0.0 | yes |
| swift-collections | **1.6.0** | 1.1.0 | yes |
| swift-cmark | **0.8.0** | 0.5.0 | yes |
| Magnet / OllamaKit / Splash (forks) | branch heads `4865f86d` / `0079411b` / `c31eba08` | same SHAs, `kind = revision` | same content, now immutable |
| MarkdownUI, NetworkImage, Sauce, WrappingHStack | 2.4.1 / 6.0.1 / 2.4.1 / 0.2.0 | identical | no |

**Finding:** none of the drifted baseline versions changed the warning set (the 2.4.0 KeyboardShortcuts API re-adds the old call as deprecated-without-warning evidently — no deprecation warning observed), but this is exactly the nondeterminism F-18 addressed: the baseline's "same code" builds differently on different days. The warning comparison holds; the *reproducibility* argument is reinforced.

---

## 5. Warning inventory by category

Occurrences per configuration: **58 macOS / 59 iOS** (Debug ≡ Release per platform). Swift 6 errors-in-waiting: **46 macOS / 43 iOS** occurrences.

| # | Category | Count (sites) | Locations | Swift 6 error? | Audit ID | Treatment |
|---|---|---|---|---|---|---|
| 1 | PersistentModel crossing actor boundaries | ~25 | ConversationStore 67,69,106,111,112,116,117,126,127,130,173,250-253,382,469; LanguageModelStore 103,106; CompletionsStore 39,43; SwiftDataService 94,96; Chat 58,75 | yes | F-07 | Architecture change (§10 Option A) |
| 2 | SwiftData `#Predicate`/`SortDescriptor` KeyPath Sendable | 9 (4 macro-generated + 5 SortDescriptor sites: SwiftDataService 48,91,134,152 + macro at source 100,123,133) | SwiftDataService fetch/delete methods | yes — **unfixable in app code** (§12) | — | Documented exception + Apple Feedback |
| 3 | MainActor isolation violations | 6 | HapticsService 19,26 (×4, iOS-only); PromptPanelView 157; Accessibility 19 | 4 of 6 | — | Batch C1: annotate `@MainActor` / hop |
| 4 | non-Sendable closure captures | 8 | Binding+Extension 13,15,16; AppStore 75,148; ConversationStore 69,116,117; RecordingView 33 | 1 (AppStore 148) | F-46 | C1 (RecordingView/Binding), C2 (AppStore) |
| 5 | unstructured Task / sending-closure | ~12 | AppStore 75,148,161; CompletionsStore 24,25,30,31,37; OllamaService 91; PanelManager 32,52; LanguageModelStore 103 | yes (most) | F-06, F-24, F-45, F-46 | C2/C4 |
| 6 | AppStore timer & reachability isolation | 6 (subset of 4+5) | AppStore 75,148,161 (+ state vars at 40-45, no diagnostic yet but race per F-46) | yes | F-06, F-46 | C4 |
| 7 | CompletionsStore isolation | 7 | CompletionsStore 24,25,30,31,37,39,43 | yes | F-25 | C2 |
| 8 | ConversationStore isolation | 17 | see category 1 + 106,126,173,382,469 sending message models | yes | F-07, F-23, F-24 | C2 (store) + C3 (persistence) |
| 9 | LanguageModelStore isolation | 2 | 103,106 | yes | — | C2 (already `@MainActor` — diagnostics stem from actor service return; resolved by C3) |
| 10 | AppKit/accessibility isolation | 3 | Accessibility 19 (`kAXTrustedCheckOptionPrompt` global), 134 (unreachable); PromptPanelView 157; PanelManager 32,52 | 1 | F-56 (dead code) | C1 |
| 11 | Deprecations | 3 | SplashSyntaxHighlighter 77 (Text `+`, macOS+iOS); SpeechRecogniser 202 (`requestRecordPermission`, iOS) | no | — | C1 |
| 12 | Unreachable code | 1 | Accessibility 134 | no | F-56 | C1 / dead-code batch |
| 13 | Asset-catalog | 2 | `bgCustom.colorset` XR `systemBackgroundColor` | no | F-33 | asset fix batch (out of scope here) |
| 14 | Benign build-tool | 1 | "first of multiple matching destinations" (appears when a destination specifier matches several) | no | — | none — already using explicit destinations |
| 15 | Dependency warnings | 0 | — | — | — | — |
| + | Generated asset symbols | 1 | `GeneratedAssetSymbols.swift`: custom `label` colorset collides with `UIColor.label` symbol (iOS) | no | — | rename colorset (asset batch) |

---

## 6. Warnings introduced by stabilization

**Net introduced: zero.** The tranche diff touched `SwiftDataService.swift` (new day-delete predicate + `init(inMemory:)` seam), `ConversationStore.swift` (rewritten `deleteDailyConversations`), `Chat.swift`, `MoltenApp.swift`, provider cancellation, logging conversions, project/manifest/test files. Fingerprint comparison shows no new warning *texts* anywhere.

**The generated-predicate trace (explicitly required):** SwiftData's `#Predicate` macro emits diagnostics from per-expansion generated buffers whose names embed the source line (`@__swiftmacro_6Molten0027SwiftDataServiceswift_ovFAhfMX<n>_24_9PredicatefMf_.swift`). Tracing each via the compiler's "in expansion of macro 'Predicate' here" notes:

| Generated file (HEAD) | Originating source expression | Diagnostics | Baseline counterpart |
|---|---|---|---|
| `…MX99_…PredicatefMf_.swift:5` | `SwiftDataService.swift:100` — `#Predicate<ConversationSD>{ $0.id == conversationId }` (getConversation, unchanged) | KeyPath<ConversationSD, UUID> | `…MX96_…` (same expression at line 97) |
| `…MX122_…PredicatefMf_.swift:6,14` | `SwiftDataService.swift:123` — **new** `#Predicate<ConversationSD> { $0.updatedAt >= startOfDay && $0.updatedAt < startOfNextDay }` (F-01/F-43 fix) | KeyPath<ConversationSD, Date> ×2 (one per key-path reference) | `…MX113_…` — the **replaced** exact-instant predicate `$0.createdAt >= date && $0.createdAt <= date` at line 114, which emitted KeyPath<ConversationSD, Date> ×2 |
| `…MX132_…PredicatefMf_.swift:6,11` | `SwiftDataService.swift:133` — `#Predicate<MessageSD>{ $0.conversation?.id == conversationId }` (unchanged) | KeyPath<MessageSD, Optional<ConversationSD>> + KeyPath<ConversationSD, UUID> | `…MX122_…` (same expression at line 123) |

Conclusion: the new day-deletion predicate emits **the same diagnostic class the predicate it replaced already emitted** (KeyPath<ConversationSD, Date>, two key-path references). The "4 new / 4 removed" fingerprint delta is entirely the `MX<line>` filename shift. No new warning *category, text, or count* entered the build. The other remediation files (cancellation, logging, manifest, tests) added zero diagnostics — verified by the zero-intersection of warning sites with the diff's added lines.

---

## 7. SwiftData ownership and actor-boundary map

**Current topology:**
- `ModelContainer` — created inside `SwiftDataService.init` (fatalError on failure — F-03), exposed as `let modelContainer`; default (on-disk) configuration; also constructible in-memory via the new `init(inMemory:)` test seam.
- `ModelContext` — **one**, private, actor-owned, `autosaveEnabled = false`; `DefaultSerialModelExecutor`. No main-actor context exists.
- `SwiftDataService` — `final actor … : ModelActor` (manual conformance), singleton `.shared` (`nonisolated(unsafe)` at use sites).
- The four `@Model` types — `ConversationSD`, `MessageSD` (cascade child), `LanguageModelSD` (unique `name`), `CompletionInstructionSD` — are created **on the MainActor** (stores/views), inserted/saved via the actor, then **mutated on the MainActor** while the actor may be saving the same instances.

**Per-method surface (all actor-isolated unless noted):**

| Method | Params with live models | Returns live models | Caller isolation | Crosses boundary? | Later mutated at | saveChanges | Related warnings |
|---|---|---|---|---|---|---|---|
| `fetchModels()` | — | `[LanguageModelSD]` ✓ | `@MainActor` LanguageModelStore | yes (out) | store builds display list | — | LMS:106; KeyPath 48 |
| `saveModels(models:)` | `[LanguageModelSD]` ✓ | — | `@MainActor` | yes (in) | — | ✓ | LMS:103 sending |
| `deleteModels()` | — | — | `@MainActor` | no | — | ✓ | — |
| `createConversation(_:)` | `ConversationSD` ✓ | — | MainActor (incl. test code) | yes (in) | — | ✓ | CS:106/126/250 sending |
| `renameConversation(_:)` | ✓ | — | MainActor | in | — | ✓ | — |
| `deleteConversation(_:)` | ✓ | — | MainActor | in | — | ✓ | — |
| `updateConversation(_:)` | ✓ (sets `updatedAt = .now`) | — | MainActor | in | — | ✓ | CS sending |
| `fetchConversations()` | — | `[ConversationSD]` ✓ | MainActor + inner **unstructured `Task(priority:)` escaping the actor** | yes (out, twice) | `DispatchQueue.main.async { conversations = … }` | — | SDS:94,96; CS:67,69,127,130 |
| `getConversation(_:)` | — | `ConversationSD?` ✓ | MainActor | yes (out) | becomes `selectedConversation` | — | macro MX99; CS:112 |
| `deleteConversations()` / `deleteConversations(_:calendar:)` | — | — | MainActor | no | — | ✓ | macro MX122 (new predicate) |
| `deleteMessages()` / `fetchMessages(_:)` | — | `[MessageSD]` ✓ | MainActor | out | `messages` array; streamed `content +=` | — | macro MX132; KeyPath 134; CS:111,116 |
| `updateMessage(_:)` | ✓ | — | MainActor **and** `Task(priority: .background)` | in (two executors!) | — | ✓ | CS:173,382,469 sending |
| `createMessage(_:)` | ✓ | — | MainActor | in | assistant message content during streaming | ✓ | CS:251,252 |
| `fetchCompletionInstructions()` | — | `[CompletionInstructionSD]` ✓ | nonisolated CompletionsStore | out | store `completions` off-main | — | CompS:39,43; KeyPath 152 |
| `updateCompletionInstructions(_:)` | ✓ (mutates `order`) | — | nonisolated | in | — | ✓ | CompS sending |
| `deleteCompletionInstruction(_:)` | ✓ | — | nonisolated | in | — | ✓ | — |
| `deleteEverything()` | — | — | MainActor (Settings) | no | — | ✓ | — |

**Data-flow diagram (live PersistentModel movement):**

```
        ┌──────────────────────────── MainActor ────────────────────────────┐
        │ SwiftUI views: read ConversationSD/MessageSD properties           │
        │   (Observation tracking of actor-context-owned models!)           │
        │ ConversationStore (@unchecked Sendable; @MainActor props):        │
        │   creates ConversationSD/MessageSD ──┐  mutates content += buffer │
        │   DispatchQueue.main.async publishes │  analytics fields, done    │
        │ LanguageModelStore (@MainActor)      │      ▲ same instances      │
        │   builds LanguageModelSD list ───────┤      │                     │
        └─────────────────────────────┬────────┼──────┼─────────────────────┘
                                      │ await  │ pass │ live models IN
                                      ▼        ▼      │
        ┌────────────── actor SwiftDataService (single ModelContext) ───────┐
        │ insert / delete / saveChanges()  ── fetch() returns live models ──┼──► back to MainActor stores
        │ fetchConversations(): inner Task ESCAPES actor to fetch           │    (non-Sendable results
        │ autosave OFF; explicit saves (also Task(priority:.background))    │     cross out — warnings
        └───────────────────────────────────────────────────────────────────┘     cat. 1 & 2)
        Nonisolated CompletionsStore also calls in/out (cat. 5/7 warnings).
```

**The core defect (F-07 made visible by warnings):** the *same instances* are registered in the actor's context, mutated on the MainActor (streaming buffer flush at `ConversationStore` ~447, analytics ~330-366), and concurrently saved from the actor (including a `Task(priority: .background)` save at ~164-166). `PersistentModel` is explicitly not Sendable — the 25 category-1/5 diagnostics are the compiler describing this race.

---

## 8. Root-cause analysis

**Systemic causes (produce whole families of warnings; need architecture, not line edits):**

1. **Dual-executor ownership of live PersistentModels** (single actor-owned context + MainActor mutation) → categories 1, parts of 5/8/9. Every fetch-return and every model parameter into the actor is a Sendable violation by Apple's design intent. ~25 warnings + a real race.
2. **Non-`@MainActor` observable stores using unstructured concurrency** (`AppStore`, `CompletionsStore`, parts of `ConversationStore`, `PanelManager`) → categories 4, 5, 6, 7. Timer/Task/DispatchQueue closures capture non-Sendable `self`/models; `sending` diagnostics. ~28 warnings — and the user-visible bugs F-06 (dead timer) and F-25 (off-main mutation) live here.
3. **SwiftData macro/KeyPath Sendability gap in the toolchain** → category 2 (9 diagnostics). `KeyPath` lacks a (conditional) `Sendable` conformance, so `#Predicate` macro-generated builders and `SortDescriptor(\Model.field)` inside Sendable-checked contexts warn. **Not addressable in application code** without unsound global conformances (§12).

**One-line / localized causes:** deprecations (Text `+`, `requestRecordPermission`), `kAXTrustedCheckOptionPrompt` global-var access, unreachable code after `return` (dead block — F-56), `RecordingView` closure capture, `Binding+Extension` helper, `HapticsService` calling `@MainActor` UIKit from nonisolated context, PromptPanelView/PanelManager isolation slips, asset-catalog color declaration, generated-symbol name collision. All safely fixable in place (§11 Batch C1).

---

## 9. Architecture alternatives

### Option A — Main-actor ownership (Apple's SwiftUI+SwiftData pattern)

`ModelContainer` created once at the app root; `container.mainContext` (a `ModelContext` bound to `@MainActor`) is the **only** context for live models; all stores annotated `@MainActor`; views keep observing models directly; provider services continue returning Sendable DTOs (`ChatCompletionResponse` structs — already the case) and stores apply deltas to main-context models; saves via autosave or explicit `save()` on main. `SwiftDataService` becomes a thin `@MainActor` facade (then optionally dissolved).

| Criterion | Assessment |
|---|---|
| Affected files | ~10: SwiftDataService (de-actor or `@MainActor` facade), 4 stores, MoltenApp/ApplicationEntry (container injection), macOS panel VM (MainActor hop), tests (already use in-memory container) |
| Migration/data risk | **None** — same store file, same schema; only the accessing context changes. No `VersionedSchema` interaction (but sequence after/with F-03 versioning for safety) |
| SwiftUI observation | **Optimal** — this is the designed pattern; `@Model` + mainContext observation works as documented |
| Streaming performance | Neutral-positive: buffer flushes already happen on MainActor; throttled saves (0.15s) on main are cheap; heavy work (image base64, F-16) moves off-main anyway |
| Testability | Good: `ModelConfiguration(isStoredInMemoryOnly: true)` + `mainContext` (existing `inMemory:` seam fits) |
| Swift 6 compatibility | Removes categories 1, 4, 5, 6, 7, 8, 9 (~46 of 58 warnings / all but the toolchain-gap KeyPath set + a few localized) |
| Incremental strategy | C2 store isolation → C3 swap actor for mainContext per store → remove actor |
| Mixed-ownership risk | **Medium during migration** — two contexts over one container materialize *distinct instances* per row; migrating store-by-store with no overlapping ownership windows is essential |
| Expected warning reduction | ~46 → ~9 (remaining: KeyPath toolchain gap ×9, asset/deprecation one-liners handled separately) |

### Option B — Actor-owned context + DTO/PersistentIdentifier boundary

Keep the `@ModelActor` service; it never returns live models — only Sendable DTO structs, primitives, or `PersistentIdentifier`s; UI observes DTOs or uses `@Query` with its own main context; all mutation stays actor-side.

| Criterion | Assessment |
|---|---|
| Affected files | ~25+: every service call site **and every view reading model properties** (views consume `ConversationSD`/`MessageSD` directly today) |
| Migration/data risk | None data-wise; very high code churn |
| SwiftUI observation | Degraded — requires a DTO↔UI projection layer; loses direct `@Model` observation ergonomics |
| Streaming performance | Per-chunk DTO mapping overhead (small) + diffing |
| Testability | Excellent (pure boundaries) |
| Swift 6 compatibility | Similar end state to A for store/service warnings; KeyPath gap remains |
| Incremental strategy | Hard — the boundary cuts through every view; big-bang pressure |
| Mixed-ownership risk | Lower (single owner), but the long transition creates dual paths |
| Expected warning reduction | Similar ultimate count at ~3× the cost |

---

## 10. Recommended architecture

**Adopt Option A**, for this repository specifically because:

1. **Live models are already UI state.** Views observe `ConversationSD`/`MessageSD` directly and the streaming pipeline mutates them on the MainActor today. Option A legalizes what the code already does; Option B fights it.
2. **Zero data risk.** Same file, same schema — critical for an App Store app with existing users (and compatible with the F-03 versioned-schema work, which should land alongside or just before).
3. **Provider boundaries are already DTO-shaped.** `ModelProviderProtocol` yields `ChatCompletionResponse` structs; no provider redesign needed.
4. **Warning payoff per change is maximal**, and the residual set is the *unfixable-in-app-code* toolchain gap (§12) — i.e., Option A takes the codebase as close to Swift 6 as the SDK currently allows.
5. Apple's own guidance for SwiftUI+SwiftData is main-actor context ownership; actor contexts (`@ModelActor`) are intended for *background import/sync* work this app doesn't have.

**Target shape:** `MoltenApp` creates the `ModelContainer` (graceful failure handling replaces `fatalError` — pairs with F-03); stores are `@MainActor` and use `container.mainContext` (injected); `SwiftDataService` is retired in stages to `@MainActor` fetch/save helpers; the in-memory seam stays for tests; macOS panel code hops to MainActor. **Not implemented here** — planning only, per instructions.

---

## 11. Incremental implementation plan

Sequenced as independently reviewable batches (letters C* to distinguish from the remediation roadmap's batches; designed to compose with it):

**C1 — Isolated mechanical warnings** (XS–S, low risk, no architecture touch)
- Scope: SplashSyntaxHighlighter Text interpolation; `requestRecordPermission` → `AVAudioApplication`; `HapticsService` `@MainActor` annotation; `kAXTrustedCheckOptionPrompt` access (localized `@MainActor` read or documented `nonisolated` safe pattern — *not* `nonisolated(unsafe)`); RecordingView closure `@MainActor`/Sendable fix; Binding+Extension helper rewrite; Accessibility unreachable code removal (only that dead block).
- Tests: existing suite green; run with Main Thread Checker; no new warnings on changed lines.
- Acceptance: categories 3, 11, 12 and the one-liners of 4/10 cleared (≈12 warnings gone); zero Swift 6 errors-in-waiting from these files.
- Excluded: store isolation, persistence, dead-code beyond the unreachable block.

**C2 — Store isolation** (S–M, medium risk)
- Scope: `CompletionsStore` → `@MainActor` (**F-25 Part A only — see note**); `AppStore` observable state + timer lifecycle on MainActor / `AsyncTimerSequence` (fixes F-06 + categories 6); `ConversationStore` DispatchQueue.main.async → direct MainActor assignment (F-24 ordering fix); `PanelManager` isolation slips.
- **F-25 is split:** Part A = store/main-actor isolation (this batch, fixes off-main Observation publication). Part B = persistent-model ownership correction — `SwiftDataService actor → [CompletionInstructionSD] → @MainActor store` remains illegal (live non-Sendable `PersistentModel` crossing the boundary) and is only fully resolved by the C3 main-context refactor.
- Prereqs: C1. Tests: backoff-math unit tests, completions load test, timer-restart test, reload-ordering test with instant mock provider; Main Thread Checker clean.
- Acceptance (revised — no exact reduction promised up front; fixes can move diagnostics to call sites): every targeted warning is either removed without replacement or documented as requiring a wider isolation change; no new warning *category* and no unsafe annotation introduced; F-06/F-24 behaviorally fixed; F-25 Part A done with Part B explicitly tracked for C3. Actual reduction calculated from clean logs afterward.
- Excluded: changing which context owns models (that's C3).

**C3 — Persistence ownership (Option A core)** (M–L, medium-high risk) — **on a separate branch, only after F-03 is completed and merged**
- Scope: container at app root with graceful-failure path; `@MainActor` mainContext as sole live-model context; de-actor `SwiftDataService` (facade first, dissolve later); remove model-crossing calls.
- Prereqs: **F-03 must be completed first, as its own change (versioned schema V1 + fixture-store tests + graceful startup failure, no model-property changes), merged and verified — never combined with this refactor** (two high-impact persistence changes in one branch would make regressions undiagnosable). The context-ownership change should not itself require a data migration, but F-03 is the safety net. C2 done so stores are MainActor-clean. **Re-measure the KeyPath/Predicate diagnostics after this refactor** — isolation changes may alter which ones occur, so the toolchain-exception list must be rebuilt from fresh logs, not assumed.
- Tests: migration fixture stores open; fetch/save through mainContext; streaming end-to-end with fake provider; **TSan-clean streaming session** (validates F-07 resolved).
- Acceptance: category 1 (+8/9) cleared (≈17-19 warnings); no dual-context instance divergence (test: same `persistentModelID` returns identical object identity from mainContext).
- Excluded: DTO refactor of views; provider protocol changes.

**C4 — Reachability/task isolation hardening** (S, low risk after C2)
- Scope: F-45 (CancellableHolder lock or single-executor confinement), F-46 (AppStore polling state confined — mostly done by C2; finish here), F-23 (generation-ID token for rapid sends).
- Tests: TSan on chat-stream + polling scenarios; rapid-send single-stream test.
- Acceptance: TSan clean; remaining category-5 warnings cleared.

**C5 — Generated/toolchain warnings** (documentation, not code)
- Scope: record the 9 KeyPath-Sendable diagnostics as documented known-warning exceptions (§12); file Apple Feedback with minimal repro; rename the `label` colorset (asset-only change) to clear the generated-symbol collision; fix `bgCustom` colorset platform declarations (pairs with F-33).
- Acceptance: CI allow-list contains exactly the toolchain-gap fingerprints; asset warnings gone.

---

## 12. Warnings that should not be "fixed" in application code

1. **SwiftData `#Predicate` / `SortDescriptor` KeyPath-Sendable diagnostics (9).** Root cause is in the SDK/compiler: `KeyPath<Root, Value>` has no `Sendable` conformance, so the `#Predicate` macro-generated builders and `SortDescriptor(\Model.field)` initializers inside Sendable-checked contexts warn — even though key paths are immutable and this is Apple's own API surface. **Reject** as solutions: `extension KeyPath: @unchecked Sendable` (globally unsound, would mask real issues app-wide, explicitly prohibited), `@preconcurrency import SwiftData` (mere silencing), moving predicate construction to detached tasks (doesn't help; the check is on the macro expansion). **Do instead:** (a) minimal repro — any `@ModelActor`/actor with `SortDescriptor(\SomeModel.field)` + `#Predicate` under `SWIFT_STRICT_CONCURRENCY = complete`; (b) file Apple Feedback (SwiftData/Foundation component) requesting conditional `Sendable` for `KeyPath` / Sendable-safe predicate macro expansion; (c) maintain a **documented known-warning exception** for exactly these fingerprints in the CI allow-list (§13). These are the gating blocker for Swift 6 mode (§14).
2. **`GeneratedAssetSymbols.swift` "label" collision** — generated-file warning; fix is *renaming the asset* (app-level, but an asset change — deferred to the asset/F-33 batch), never suppression.
3. **`xcodebuild: WARNING: Using the first of multiple matching destinations`** — build-tool note, benign; already using explicit destinations in CI-style commands; no action.
4. **actool `bgCustom` XR color warnings** — asset-catalog declaration issue, not Swift; fix with the colorset (F-33 batch), not code.

---

## 13. Proposed CI no-new-warnings policy

- **Gate:** every CI build parses xcodebuild logs into normalized fingerprints (same normalization as §2: repo-path relativization, generated-path canonicalization, macro-filename → originating-source-expression mapping via expansion notes, text-exact matching).
- **Keep the baseline small and temporary.** A 55-fingerprint permanent allow-list would normalize technical debt. Instead track: (a) warning *counts by category* as the trend metric; (b) raw build logs as CI artifacts; (c) a narrowly scoped allow-list **only for confirmed toolchain/generated diagnostics** (the KeyPath-Sendable set, and only while re-measurement after each architecture batch confirms they persist). PRs fail on any fingerprint outside this narrow list. **After C1–C4 complete, the allow-list must contain only generated/toolchain warnings** — everything application-authored is expected at zero.
- **Two tiers:** (1) *block* on any new warning outside the allow-list; (2) *report-only* for the documented toolchain-gap fingerprints (KeyPath-Sendable) so a future SDK fix is noticed (they'll disappear → prompt baseline cleanup).
- **Matrix:** macOS Debug+Release, iOS Simulator Debug+Release, same destinations/Xcode pinned in CI; `CODE_SIGNING_ALLOWED=NO`; clean DerivedData.
- **Do not** adopt `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` wholesale while the toolchain-gap diagnostics exist — it would break the build through no app-code fault. It becomes appropriate at the Swift 6 gate (§14) with the fingerprint exceptions handled by the parser, not the compiler flag.

---

## 14. Swift 6 readiness gate

Current state: Swift 5 mode + strict-concurrency-complete; **46 (macOS) / 43 (iOS)** occurrences explicitly state "this is an error in the Swift 6 language mode."

**Gate criteria (all required before flipping `SWIFT_VERSION = 6`):**
1. Zero errors-in-waiting from application-authored code — i.e., batches C1–C4 complete (categories 1, 3–10 cleared).
2. The residual KeyPath-Sendable diagnostics (category 2) are either (a) resolved by an SDK update (re-verify each Xcode), or (b) confirmed to still warn-as-error in Swift 6 mode, in which case Swift 6 mode **remains blocked on Apple** (tracked via the Feedback from §12) — do not work around with unsound conformances. *Test this empirically on a throwaway branch (`SWIFT_VERSION = 6`) after C1–C4: if the macro diagnostics become hard errors, the gate is not passable yet regardless of app code.*
3. TSan-clean streaming + polling sessions (validates F-07/F-45/F-46 actually resolved, not just compile-clean).
4. CI no-new-warnings policy (§13) live, with warnings-as-errors adopted *after* the exception list is proven exact.
5. Full regression suite (remediation §13 starter suite + C-batch tests) green on macOS + iOS Simulator.

---

## 15. Suggested prompt for the first safe implementation batch

```
Implement Batch C1 (isolated mechanical concurrency warnings) from
CONCURRENCY_WARNING_AUDIT.md §11 in /Users/eplt/SCM/molten.

Scope — ONLY these warnings/files:
1. Molten/Extensions/SplashSyntaxHighlighter+Extension.swift:77 — replace
   deprecated Text '+' concatenation with string interpolation per the
   deprecation message.
2. Molten/UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift:202 —
   migrate AVAudioSession.requestRecordPermission to the
   AVAudioApplication API named in the deprecation message, preserving the
   existing granted/denied behavior.
3. Molten/Services/HapticsService.swift:19,26 — annotate the type (or the two
   methods) @MainActor so UIKit generator calls are main-actor-isolated;
   update call sites if needed (they are UI event handlers).
4. Molten/Helpers/Accessibility.swift:19 — fix the kAXTrustedCheckOptionPrompt
   access isolation without nonisolated(unsafe) (e.g. perform the access
   inside a @MainActor/isolated helper); also remove the dead code after the
   return at :134 (that block only).
5. Molten/UI/Shared/Chat/Components/Recorder/RecordingView.swift:33 — make the
   onCompleteClosure capture concurrency-safe (mark the closure type
   @Sendable or isolate appropriately) without changing behavior.
6. Molten/Extensions/Binding+Extension.swift:13,15,16 — rewrite the onChange
   helper so it has no non-Sendable captures in @Sendable closures; if it has
   zero callers, leave it and report instead (verify with grep first).

Hard constraints:
- Do NOT add @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or any
  warning-suppression flags/attributes.
- Do NOT change SWIFT_VERSION or SWIFT_STRICT_CONCURRENCY.
- Do NOT touch stores (AppStore/CompletionsStore/ConversationStore/
  LanguageModelStore), SwiftDataService, persistence, providers, project
  settings, Package.resolved, manifests, plists, entitlements, or assets.
- Preserve behavior exactly; no reformatting of unrelated code.
- Do NOT attempt the SwiftData KeyPath-Sendable warnings (§12 — toolchain gap,
  explicitly out of scope).

Preflight (run, report, stop-and-ask if unexpected):
pwd; git status --short; git branch --show-current; git rev-parse HEAD;
git log -1 --oneline. Expected: /Users/eplt/SCM/molten, branch
audit/ios-review, HEAD ea84611 or documented successor. Do not modify main;
no push/merge/rebase/amend/tag.

Verification (all required, record exact commands + results):
- Clean Debug AND Release builds for macOS ('platform=macOS') and iOS
  Simulator ('platform=iOS Simulator,name=iPhone 17,OS=26.5'),
  CODE_SIGNING_ALLOWED=NO, fresh DerivedData: all must BUILD SUCCEEDED.
- xcodebuild test -scheme Molten on both destinations (existing tests green).
- Warning delta: extract fingerprints from the new logs and prove (a) the six
  target warning texts are gone, (b) no new fingerprint appears anywhere,
  (c) errors-in-waiting occurrence counts dropped by exactly the number of
  Swift-6-flagged targets fixed (report before/after counts per platform).
- Main Thread Checker: run the app briefly (or reason per call site) to
  confirm the @MainActor annotations introduce no main-thread violations.
- git diff self-review per commit; one commit per warning group; final
  git status --short.

Finish with an evidence report: preflight, commits (hashes+subjects), warning
before/after tables, build/test results, and confirmation no out-of-scope
files changed. Stop there — do not start C2.
```
