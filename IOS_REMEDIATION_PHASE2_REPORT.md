# Molten — Remediation Phase 2 Report

**Date:** 2026-08-02 · **Branch:** `audit/ios-review` (continued; `main` untouched at `af7ba46`) · **Executed per:** `IOS_REMEDIATION_PART2.md` ("Phase 2 — Remaining small correctness fixes", F-25 explicitly excluded)

---

## 1. Starting state (preflight)

- Repo `/Users/eplt/SCM/molten`; branch `audit/ios-review`; HEAD `ea84611` (test(F-17)…); merge-base with `main` = `af7ba46`.
- Working tree clean except five untracked documentation files (the three audit reports, `CLAUDE.md`, and your `IOS_REMEDIATION_PART2.md` feedback doc).
- Build environment: Xcode 26.6 (17F113); Swift 5.0 + `SWIFT_STRICT_CONCURRENCY = complete`; destinations macOS + iOS Simulator (iPhone 17, iOS 26.5).

## 2. Commits created (oldest → newest)

| Hash | Subject | Files |
|---|---|---|
| `29419f0` | fix(F-20): surface prompt setup failures as recoverable error state | ConversationStore.swift, ConversationStoreErrorTests.swift (new), project.pbxproj |
| `5fafc2e` | fix(F-26): send full conversation history to Apple Foundation provider | AppleFoundationService.swift, ApplePromptTests.swift (new), project.pbxproj |
| `17d0998` | fix(F-42): add explicit timeouts to Swama requests | SwamaService.swift, SwamaRequestTests.swift (new), project.pbxproj |
| `a03c913` | fix(F-44,F-48): honor Ollama bearer token parameter on all endpoint paths | OllamaService.swift |
| `fc116f6` | fix(O-02): restore default model selection across launches | Chat.swift |
| `73b32d4` | fix(day-delete): clear selection only on successful deletion; add DST coverage | ConversationStore.swift, DayDeletionTests.swift |

Cumulative since `af7ba46`: 26 files, +908/−160 (includes the prior stabilization tranche). Phase 2 alone: 8 files touched.

## 3. Finding-by-finding disposition

| Finding | Status | What changed |
|---|---|---|
| **F-20** | **IMPLEMENTED — targeted failure-path verification pending** | `sendPrompt` setup (updateConversation + 2× createMessage + reloadConversation) wrapped in do/catch; failure now sets `conversationState = .error(message:)` directly — deliberately *not* via `handleError`, which flags `messages.last` (may not exist yet or belong to a previous conversation). UI recovers on next send. The unknown-provider test verifies the terminal error state through a *different* path; no test yet forces `updateConversation`/`createMessage`/`reloadConversation` themselves to throw. This is a testability gap, not a known defect — a minimal throwing persistence seam can arrive with the persistence architecture work (Phase 4/5); `SwiftDataService` is deliberately not distorted now to force it. Implementation is mergeable. |
| **F-26** | **Complete** | Apple provider now sends the full formatted multi-turn history (system/user/assistant) instead of only the last user message; prompt assembly extracted to `AppleFoundationService.constructPrompt(from:)` (internal static) and unit-tested. |
| **F-42** | **IMPLEMENTED — live stream-timeout behavior pending on-device verification** | `SwamaService.makeRequest(path:method:timeout:accept:)` centralizes URL/method/timeout/headers; timeouts: model list 15 s, stream request 120 s, non-streaming completion 300 s. `getModels`/`chatStream`/`chat` converted; the 2 s `reachable()` probe untouched. Note: `URLRequest.timeoutInterval` is **not** a guaranteed "stream-start-only" timeout — its practical behavior for long-running and stalled streams depends on the loading system and remains to be verified on device (Phase 2 smoke test: slow-but-active Swama stream longer than two minutes). Confirmed: the code sets **no** `URLSessionConfiguration.timeoutIntervalForResource` override anywhere (grep-verified), so no short total-lifetime limit is imposed on legitimate generations — `URLSession.shared` defaults apply. |
| **F-44/F-48** | **Complete** | `initEndpoint` resolves explicit param > stored token, empty = no token, and now passes the token on **both** the configured-URL and default-localhost paths; the hardcoded placeholder token literal was removed (grep confirms 0 occurrences; value not reproduced anywhere). Settings call sites unchanged and compatible. |
| **O-02** | **Complete** | `Chat` now reads the `defaultModel` key that Settings already writes (no key rename; existing stored values are honored) — the default model survives relaunch. |
| **Day-delete error path** (status §11 risk 1) | **IMPLEMENTED — success path and calendar behavior verified; injected deletion-failure test pending** | `deleteDailyConversations` clears the open conversation only after a successful delete; on failure the selection is kept and the error is surfaced (`conversationState = .error`). No test yet causes `deleteConversations` to throw (same seam caveat as F-20; deferred to the persistence architecture work). |
| **DST coverage** (status §11 risk 2) | **Complete (fully verified)** | Two service-level tests: 23-hour spring-forward (2026-03-08) and 25-hour fall-back (2026-11-01) days in `America/Los_Angeles`, including a 23:30 conversation on the long day; sanity asserts confirm the day lengths. |
| **F-25** | **Excluded — by your instruction** | Classified per your feedback as Part A (store isolation → Phase 3/C2) + Part B (persistent-model ownership → Phase 5). Not touched in this phase. |

## 4. Build matrix (clean, `CODE_SIGNING_ALLOWED=NO`)

| Platform | Configuration | Destination | Result |
|---|---|---|---|
| macOS | Debug | `platform=macOS` | **BUILD SUCCEEDED** (also exercised via test runs) |
| macOS | Release | `platform=macOS` | **BUILD SUCCEEDED** |
| iOS Simulator | Debug | iPhone 17 / iOS 26.5 | **BUILD SUCCEEDED** (via test run) |
| iOS Simulator | Release | iPhone 17 / iOS 26.5 | **BUILD SUCCEEDED** |

All four are complete builds (through linking/asset catalogs), not Swift-only.

## 5. Test inventory and results

**16/16 pass on both macOS and iOS Simulator destinations** (0 failures, 0 skipped; re-verified on the final committed tree).

| Suite | Tests | Behavior exercised |
|---|---|---|
| DayDeletionTests (6) | target-day-only deletion (non-UTC calendar), explicit persistence, selection preserved across days, selection cleared when deleted, **spring-forward 23-h day**, **fall-back 25-h day** | `SwiftDataService.deleteConversations(_:calendar:)` + `ConversationStore.deleteDailyConversations` — production code, in-memory container |
| ConversationStoreErrorTests (2) | unknown-provider → terminal `.error` state; blank-prompt guard | `ConversationStore.sendPrompt` error/recovery path |
| ApplePromptTests (5) | multi-turn ordering, earlier-turn preservation, multimodal text joining, nil-content skipping, empty history | `AppleFoundationService.constructPrompt` |
| SwamaRequestTests (3) | GET/POST method+timeout+headers, SSE Accept header, timeout constants (15/120/300) | `SwamaService.makeRequest` |

**Known test gap (documented, not hidden):** forcing a *throwing* `SwiftDataService` (to exercise the new setup/delete catch branches directly) requires a persistence seam — deferred to Phase 4/5. Both new catch branches share the `.error` terminal state that `ConversationStoreErrorTests` verifies end-to-end.

## 6. Warning delta

Compared against the pre-Phase-2 clean logs from the concurrency audit (same methodology: project-source fingerprints + Swift-6-in-waiting counts):

| | macOS Release | iOS Release |
|---|---|---|
| Before (ea84611) | 40 fingerprints / 42 errors-in-waiting occurrences | 40 / 39 |
| After (73b32d4) | 40 / 42 | 40 / 39 |
| New fingerprints | **none** | **none** |
| Removed | none | none |

**Zero new warnings; zero movement in Swift 6 errors-in-waiting.** No unsafe annotation (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`) or suppression introduced.

## 7. Constraints honored

- F-25 excluded, as instructed.
- No SwiftData model declarations or schema/migration changes; no UserDefaults key renames; no Keychain work; no ATS/entitlement/plist/manifest/deployment-target/bundle-ID/signing changes; `Package.resolved` untouched (verified); no new dependencies; no provider-dispatch refactor; no dead-code cleanup or unrelated reformatting (`git diff --check` clean on every commit).
- No push/merge/rebase/amend/tag; `main` untouched.

## 8. Report adjustments applied (per your feedback in `IOS_REMEDIATION_PART2.md`)

`CONCURRENCY_WARNING_AUDIT.md` updated in place (documentation only):
1. KeyPath/Predicate warnings reworded: "no safe application-level fix identified" rather than "definitively unfixable", with an explicit re-measure-after-refactor note.
2. F-03 and the context-ownership refactor separated: F-03 must complete and merge first, on its own; the ownership change happens on a separate branch afterward.
3. F-25 split into Part A (store isolation, C2) and Part B (model-ownership correction, C3/Phase 5).
4. C1/C2 acceptance criteria: no exact warning reduction promised; "removed without replacement or documented as needing a wider change; no new category or unsafe annotation."
5. CI policy: baseline kept small and temporary (category counts + raw logs + narrow toolchain-only allow-list; toolchain-only after C1–C4).

## 9. Phase 1 status (manual items — not executable here)

Still pending, per your execution order:
1. Physical-iPhone Local Network prompt + LAN connection test (F-11).
2. Live Stop behavior vs Swama (F-05).
3. Live Stop behavior vs Apple Foundation Models (F-05).
4. Unsigned archive inspection: privacy manifest, local-network description, and **no `MoltenTests.xctest` in the archive**.
5. Committing the audit documents — left uncommitted for you (the four `.md` reports + `CLAUDE.md` remain untracked); say the word and I'll commit them on this branch.

## 10. Manual verification still required for Phase 2 items

- **F-44/F-48:** token-only configuration against a token-protected local Ollama (no automated seam yet).
- **O-02:** set default model in Settings → relaunch → selector restores it.
- **F-42:** optional — stalled/black-hole endpoint fails within the configured timeouts.
- **F-26:** two-turn Apple-provider conversation referencing turn one on Apple Intelligence hardware.

## 11. Next step

**Phase 3 — C1 mechanical warnings**, on a dedicated branch (`fix/ios-audit-warning-cleanup`) using your revised C1 prompt from `IOS_REMEDIATION_PART2.md` verbatim. Phases 4–6 (F-03 versioned schema → main-actor SwiftData ownership on a separate branch → timer/task isolation) remain sequenced after it, with KeyPath warnings re-measured before any permanent allow-list.
