---
report_id: "2026-08-02-audit-remediation-round-1"
title: "Audit remediation round 1 and v1.1 release preparation"
date: "2026-08-02"
stage: "remediation"
status: "complete"
branch: "main"
from_commit: "af7ba46"
to_commit: "a9cc893"
working_tree_clean: false
previous_report: null
related_audit: "IOS_TECHNICAL_AUDIT.md (internal document, untracked by repository policy — see §2)"
related_findings:
  - "F-01"
  - "F-43"
  - "F-02"
  - "F-18"
  - "F-05"
  - "F-10"
  - "F-11"
  - "F-12"
  - "F-59"
  - "F-17"
  - "F-19"
  - "F-20"
  - "F-26"
  - "F-42"
  - "F-44"
  - "F-48"
  - "O-02"
  - "AN-1..AN-8 (ANALYTICS_REVIEW.md)"
generated_by: "AI-assisted repository analysis"
---

# Audit remediation round 1 and v1.1 release preparation

## 1. Executive summary

This milestone is the first development report for this repository and the first use of the milestone-reporting system; it is therefore an **initial retrospective baseline report** covering the technical audit of the v1.0.1 release and the remediation work that followed.

**Purpose:** remediate the findings of the initial technical audit (`IOS_TECHNICAL_AUDIT.md`, internal), prepare the v1.1 release, and establish repository hygiene (tests, reproducible builds, documentation policy).

**Achieved:** the P0 data-loss defect fixed with regression tests (including DST coverage); the macOS clean-checkout build restored and dependency resolution made reproducible; stream cancellation implemented for the two providers missing it; privacy manifest and iOS local-network usage description added; all sensitive release logging removed; the project's first test target created (28 tests); per-message analytics reworked to prefer server-reported statistics; a user-facing provider relabel ("1. Ollama API" / "2. OpenAI API", `1:`/`2:`/`A:` model prefixes); README, repository description, and topics refreshed; version bumped to 1.1 (build 5); all remediation work squash-merged to `main` via PR #1.

**Completion state:** complete for the committed scope. Two findings (F-05, F-11) are implemented but require physical-device verification; a large share of the original audit backlog was deliberately deferred (see §5, §14).

**Most important remaining risks:** (1) no versioned SwiftData schema (F-03) — any future model change risks launch failures for existing installs; (2) unverified on-device behavior (LAN permission prompt, live Stop behavior) was accepted by the product owner as a merge-time risk; (3) bearer tokens remain in `UserDefaults` (F-09).

**Readiness:** v1.1 code is merged and release-prepared (unsigned archive inspected; tag/release not yet created). The recommended next milestone is the persistence safety foundation (F-03), not new features.

## 2. Reporting scope and baseline

- **Previous report:** none — first use of the reporting system.
- **Baseline selection:** `af7ba46` ("Release v1.0.1", tag `v1.0.1`) was chosen as the period start: it is the most recent release tag, and the initial technical audit explicitly documented the repository state at that commit. This is an inferred-but-well-evidenced baseline, labeled as such per the initial-report guidance.
- **Commit range:** `af7ba46..a9cc893` on `main`.
  - Remediation work happened on branch `audit/ios-review` (20 commits, `20afb3e..ccc046b`, 2026-08-01 18:23 → 2026-08-02 02:44 +0800) and reached `main` as a **squash merge** via PR #1 (merge commit `d4e75ed`, merged 2026-08-01T18:55:25Z, `gh` record verified), followed by `a9cc893` (README refresh).
  - The granular 20-commit chain is still recoverable from the object database (`git log af7ba46..ccc046b`) although the branch ref was deleted after merging; it may be lost to garbage collection. The chain is cited throughout this report as implementation evidence.
- **Included work:** all code, test, configuration, and documentation commits in the range; repository metadata updates (description/topics via `gh`, no commit).
- **Excluded work:** internal audit/process documents — by repository policy adopted during this milestone they are untracked and gitignored (§8, D-4); they exist on disk and are cited as internal evidence but are not part of the committed tree.
- **Working-tree state at report generation:** not clean — one untracked file created by a conversation export (`2026-08-02-111546-command-messageinitcommand-message.txt`, repository root). Not attributed, not included as completed work; see §14.
- **Baseline uncertainties:** the audit's findings were authored against `af7ba46` but the audit document itself is untracked; finding IDs (F-*, O-*, AN-*) are stable only within the on-disk internal documents. No issue tracker is used by this repository.

## 3. Goals and planned work

**Documented goals** (from on-disk plans: `IOS_TECHNICAL_AUDIT.md` roadmap, `IOS_REMEDIATION_STATUS.md`, `IOS_REMEDIATION_PART2.md`/`IOS_REMEDIATION_PHASE2a.md` review feedback, `ANALYTICS_REVIEW.md`):

1. Fix the P0 day-deletion data-loss defect (F-01/F-43).
2. Restore the macOS clean-checkout build and make dependency resolution reproducible (F-02/F-18).
3. Implement stream cancellation for Swama and Apple providers (F-05).
4. Add the app privacy manifest and iOS local-network usage description (F-10/F-11).
5. Remove sensitive release logging (F-12/F-59).
6. Create the first unit-test target (F-17).
7. "Phase 2" small correctness batch: F-20, F-26, F-42, F-44/F-48, O-02 — explicitly excluding F-25 (per review feedback, split into store isolation vs. model-ownership parts).
8. Day-delete hardening: selection semantics on failure + DST test coverage.
9. User-facing provider relabel (OpenAI-compatible branding, oMLX endorsement).
10. Analytics accuracy remediation (AN-1…AN-8) after a dedicated review.
11. v1.1 release preparation: version bump, archive inspection, README and repository metadata refresh.

**Goals inferred from changes** (not separately documented): squash-merge strategy to keep internal documents out of `main` history; repository description/topics update aligned with the relabel.

## 4. Work completed

### 4.1 Audit remediation — correctness (commits `20afb3e`, `29419f0`, `5fafc2e`, `fc116f6`, `73b32d4`, `76bc319`)

- **Day deletion (F-01/F-43, P0):** `SwiftDataService.deleteConversations(_:calendar:)` now deletes by a half-open calendar-day interval on `updatedAt` (`startOfDay ..< startOfNextDay`), matching the sidebar grouping (`Calendar.current.startOfDay(for: updatedAt)` in `ConversationHistoryListView`); explicit `saveChanges()`. `ConversationStore.deleteDailyConversations(_:)` became `@MainActor async`, reloads history, and clears the open conversation only when it belonged to the deleted day; failures surface as an error state instead of silently clearing selection (`73b32d4`).
  - User-visible: the per-day context-menu action deletes exactly one day. Compatibility: none (behavior correction). Verified by 6 tests including DST transitions (§9).
- **Prompt double-send (F-19):** history construction extracted to `ConversationStore.messageHistory(from:)`; the manual second append of the current user message removed; empty assistant placeholders skipped. User-visible: single prompt per turn (previously every turn sent the latest user message twice). Verified by history-uniqueness tests.
- **Setup-failure recovery (F-20):** `sendPrompt` setup wrapped in do/catch → `.error(message:)` state instead of a permanent spinner. Verified via the unknown-provider terminal-state test; a forced-`SwiftDataService`-throw test is not yet possible (no seam — §15).
- **Apple provider history (F-26):** `AppleFoundationService` now sends the full formatted multi-turn history; assembly extracted to a tested static (`constructPrompt(from:)`).
- **Default model persistence (O-02):** `Chat` reads the `defaultModel` key that Settings writes (no key rename). Not device-verified (§15).

### 4.2 Build and release configuration (commits `ab22331`, `7eeb018`, metadata via `gh`)

- **Reproducible resolution (F-02/F-18):** fork branch-pins (Magnet, OllamaKit, Splash) converted to immutable revisions; KeyboardShortcuts pinned `exactVersion 2.0.1`; `Package.resolved` un-ignored and committed; `MoltenApp.swift` updated to `onKeyboardShortcut` (the API the pinned version exposes). Clean resolve verified byte-stable during the milestone (fresh DerivedData).
- **Version 1.1 / build 5** (`7eeb018`): `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in both project and target configs; verified in the built product (1.1 / 5).
- **Archive inspection:** unsigned `xcodebuild archive` (Release, generic iOS) inspected during the milestone — no `*Tests.xctest` shipped, app-level `PrivacyInfo.xcprivacy` present, usage descriptions present.
- **Repository metadata:** description and 16 topics updated via `gh repo edit` to match the OpenAI-compatible positioning (verified via `gh repo view`).

### 4.3 Concurrency / cancellation (`631272e`)

- **F-05:** Swama and Apple stream producers retain their producer `Task` and register `continuation.onTermination = { task.cancel() }`, mirroring Ollama's existing pattern (`grep continuation.onTermination` → 1 per provider service). Verified structurally + by tests/builds; live stop behavior requires device verification (§15).

### 4.4 Security and privacy (`3a307c6`, `173a45d`)

- **F-10:** `Molten/PrivacyInfo.xcprivacy` added to the target (tracking=false, no tracking domains, UserDefaults category with reason CA92.1). Present in built products (verified).
- **F-11:** `NSLocalNetworkUsageDescription` added via `INFOPLIST_KEY_` (iOS). Present in built product Info.plist (verified); on-device prompt behavior unverified (§15).
- **F-12/F-59:** all payload logging removed (request bodies, prompts/responses, selected text, profane placeholders); remaining diagnostics converted to `os.Logger` with `privacy: .private`. No active `print`/`NSLog` of sensitive content remains in compiled sources (verified by search).

### 4.5 Testing (`ea84611` + per-feature test commits)

- **F-17:** `MoltenTests` hosted unit-test target created and wired into the shared scheme. Grew to **5 suites / 28 tests**: `DayDeletionTests` (6), `ConversationStoreErrorTests` (2), `ApplePromptTests` (5), `SwamaRequestTests` (3), `AnalyticsTests` (12). All green on macOS and iOS Simulator during the milestone; re-verified at report generation time (macOS, §9).
- Testability pattern established: provider/analytics logic extracted as pure internal statics (`messageHistory`, `constructPrompt`, `makeRequest`, `computeAnalytics`, `promptCharacterCount`, `usageFromOllama`) — deterministic tests without live servers.

### 4.6 Networking (`17d0998`, `a03c913`)

- **F-42:** explicit Swama request timeouts (model list 15 s, stream start 120 s, non-streaming completion 300 s) via a tested `makeRequest` helper; no `timeoutIntervalForResource` override (long generations not lifetime-capped — verified by search).
- **F-44/F-48:** `OllamaService.initEndpoint` honors the `bearerToken` parameter (previously shadowed by a UserDefaults read) and passes it on the default-localhost path; the hardcoded placeholder token literal removed (search-verified: 0 occurrences).

### 4.7 Analytics accuracy (`992feea`, `3cb5bd7`) — newly scoped during this milestone

Not in the original audit; scoped by a dedicated review (`ANALYTICS_REVIEW.md`, internal).

- **AN-1:** Ollama's final-chunk counters (`promptEvalCount`/`evalCount`, ns durations) mapped into `Usage` (ns→s) via `OllamaService.mapResponse`/`usageFromOllama` (previously hardcoded `usage: nil`).
- **AN-2:** `Usage` extended with `prompt_eval_duration`/`eval_duration`/`total_duration` and Swama's `response_token/s` (CodingKeys maps the slashed wire key); previously dropped by `Codable`.
- **AN-3:** first-token timestamp stamps on the first **non-empty content** chunk (Swama leads with a role-only chunk — discovered via live SSE capture).
- **AN-4:** prompt-character estimate includes the same-timestamp current user turn and skips empty placeholders (`promptCharacterCount(for:)`); image bytes deliberately uncounted (model-specific tokenization — documented limitation).
- **AN-6:** footer suppresses rates for the Apple Foundation provider (simulated streaming, no usage) and marks its tokens `(est.)`.
- **AN-7:** `stopGenerate` records partial analytics (elapsed + token counts, server usage when available).
- **AN-8:** arbitrary `total/3` fallback split removed; `computeAnalytics` (pure) prefers server values, uses client timing as fallback (Swama total-only case keeps the client prompt/eval split bounded by the server total).

### 4.8 UI / product / documentation (`fa692ba`, `a9cc893`, metadata)

- **Relabel:** Settings sections "1. Ollama API"/"2. OpenAI API"; model prefixes `1:`/`2:`/`A:` (`ModelProvider.displayPrefix`/`displayName`); error and empty-state strings renamed consistently. Internal service names and UserDefaults keys intentionally unchanged.
- **README refresh:** OpenAI-compatible backend framing with verified oMLX details (default `http://localhost:8000`; Molten appends the `/v1` paths), deployment targets corrected to 26.0+, working test commands, roadmap ticked.
- **Internal-doc policy:** internal documents untracked and gitignored (`ccc046b`); only code and public release documents are checked in.

## 5. Finding and task status

| ID | Description | Previous status | Current status | Evidence | Verification |
|----|-------------|-----------------|----------------|----------|--------------|
| F-01/F-43 | Per-day deletion deleted all conversations; broken predicate | Open (P0) | **Completed & verified** | `SwiftDataService.swift` half-open `updatedAt` interval; `20afb3e`, `73b32d4` | 6 DayDeletionTests incl. DST, green at report time |
| F-02/F-18 | macOS build broken; unreproducible resolution | Open (P1) | **Completed & verified** | revision pins + committed `Package.resolved`; `ab22331` | clean resolve byte-stable; macOS builds green |
| F-05 | Stop doesn't stop Swama/Apple streams | Open (P1) | **Completed — device verification pending** | `continuation.onTermination` in both services; `631272e` | structural + builds; live stop unverified |
| F-10 | Missing app privacy manifest | Open (P1) | **Completed & verified** | `Molten/PrivacyInfo.xcprivacy`; `3a307c6` | present in archive + built products |
| F-11 | Missing local-network usage description | Open (P1) | **Completed — device verification pending** | `INFOPLIST_KEY_NSLocalNetworkUsageDescription`; `3a307c6` | present in built Info.plist; prompt unverified |
| F-12/F-59 | Sensitive/inappropriate release logging | Open (P1) | **Completed & verified** | `173a45d`; os.Logger conversions | search: no sensitive prints in compiled sources |
| F-17 | No test target | Open (P1) | **Completed & verified** | `MoltenTests/` (5 suites); `ea84611` | 28/28 green (report-time re-run) |
| F-19 | User prompt sent twice per turn | Open (P2) | **Completed & verified** | `messageHistory(from:)`; `76bc319` | history-uniqueness tests |
| F-20 | Setup failure → permanent spinner | Open (P2) | **Completed, partially verified** | do/catch → `.error`; `29419f0` | terminal-state test; forced-throw test not yet possible (§15) |
| F-26 | Apple provider dropped conversation history | Open (P2) | **Completed & verified** | `constructPrompt(from:)`; `5fafc2e` | 5 ApplePromptTests |
| F-42 | No Swama request timeouts | Open (P3) | **Completed & verified** | `makeRequest` + constants; `17d0998` | 3 SwamaRequestTests |
| F-44/F-48 | Ollama token parameter ignored; placeholder literal | Open (P3) | **Completed, not device-verified** | `a03c913`; literal grep = 0 | builds; token flow unverified on device |
| O-02 | Default model not persisted across launches | Open (Observation) | **Completed, not device-verified** | `fc116f6` | code-level; relaunch flow unverified |
| AN-1…AN-8 | Analytics accuracy (not in original audit) | n/a (newly scoped) | **Completed & verified** | `3cb5bd7` | 12 AnalyticsTests |
| F-25 | CompletionsStore off-main mutation | Open (P2) | **Deferred (split)** | review feedback: Part A store isolation / Part B model ownership | — |
| F-03 | No versioned SwiftData schema | Open (P1) | Deferred | audit | next milestone (§16) |
| F-06 | Reachability timer dies after backoff | Open (P1) | Deferred | audit | Phase: concurrency |
| F-07 | Cross-actor PersistentModel mutation | Open (P1) | Deferred | audit | Phase: concurrency (after TSan repro) |
| F-08 | Apple `reachable()` can trap on unsupported hardware | Open (P1) | Deferred | audit | Phase: concurrency |
| F-09 | Bearer tokens in plaintext UserDefaults | Open (P1) | Deferred | audit | Phase: secrets/policy |
| F-13 | Zero accessibility labels | Open (P1) | Deferred | audit | Phase: accessibility |
| F-14 | Dynamic Type unsupported | Open (P1) | Deferred | audit | Phase: accessibility (separate from labels) |
| F-50 | Missing encryption declaration | Open (P3) | Deferred (compliance sign-off needed) | audit | release checklist |
| F-51 | No CI | Open (P3) | Deferred | audit | post-F-03 |
| Remaining P2/P3/Observation backlog (~40 items) | see audit | Open | Deferred | audit | future milestones |

## 6. Significant implementation details

- **Day-deletion semantics:** interval is computed on `updatedAt` (what the UI groups by), not `createdAt` — a deliberate departure from the original broken predicate which filtered `createdAt` while the UI grouped by `updatedAt`. Calendar is `Calendar.current` end-to-end (grouping, store, selection check).
- **Selection preservation:** decided before deletion via `Calendar.current.isDate(_:inSameDayAs:)`; on service failure the selection is kept and the error surfaced. `handleError` could not be reused because it early-returns when `messages` is empty and flags the last message (§7, ND-4).
- **Usage wire compatibility:** `Usage` additions are optional fields with explicit `CodingKeys`; `response_tokens_per_second` maps the slashed Swama key `response_token/s`. Minimal payloads (three counts) still decode.
- **Analytics composition rule:** server durations win where present; for Swama (total only) the client first-token split is kept *bounded by the server total* — a hybrid documented in `computeAnalytics`.
- **Stop path:** partial analytics recorded only for in-flight assistant messages; `lastUsage` reset in `resetStreamingState`.
- **Compatibility invariants preserved:** SwiftData models unchanged in range (`git diff af7ba46 a9cc893 -- Molten/SwiftData/` empty); UserDefaults keys unchanged (`swamaUri`, `swamaApiKey`, `defaultModel`, …); ATS unchanged; deployment targets unchanged (26.0).
- **Deliberately unchanged:** internal type/service names (`SwamaService` etc.); `MenuBarControlView` dead placeholder; Swama SSE parser internals (F-27 deferred); concurrency architecture (F-07 deferred).
- **Test seam policy:** pure internal statics rather than DI; provider dispatch singletons untouched.

## 7. Unexpected discoveries and complications

**ND-1 — Baseline macOS build was broken by dependency drift.**
Expectation: baseline builds. Actual: fresh baseline resolution pulled KeyboardShortcuts **2.4.0** (vs 2.0.1 at audit time); the build's success/failure depended on the day's resolution. Root cause: **confirmed** — gitignored `Package.resolved` + `upToNextMajor` requirement + upstream API removal/re-addition. Impact: elevated F-02/F-18 urgency. Resolution: immutable pins + committed lockfile. Remaining: none for this item. Earlier detection: a baseline rebuild in the audit itself (later added to the concurrency audit's method).

**ND-2 — Analytics accuracy was outside the original audit's scope.**
Expectation: the audit covered user-visible behavior. Actual: the per-message analytics were fabricating Ollama numbers (`usage: nil`) — discovered only by a dedicated later review. The audit **understated** scope: it treated analytics as a feature, not as data-accuracy surface. Resolution: AN-1…AN-8 remediated. Earlier detection: audit prompts should include a data-accuracy pass over every user-visible metric (see §13).

**ND-3 — F-19 interacted with analytics wiring.**
Expectation (audit): F-19 was a P2 quality issue. Actual: once server statistics were wired, the duplicate prompt would have inflated *server-reported* prompt counts — the metric itself would expose the bug. Complexity/priority **understated** by the audit. Resolution: F-19 fixed before analytics wiring (sequencing decision). Earlier detection: dependency analysis between correctness findings and metric sources during planning.

**ND-4 — `handleError` design constrained error-path fixes.**
Expectation: reuse `handleError` for F-20/day-delete failures. Actual: it early-returns on empty `messages` and flags the last message — unsuitable for setup-time failures. Root cause: **confirmed** (code shape). Impact: bespoke error handling in both paths; `handleError` itself remains unrefactored (minor debt). Earlier detection: audit to trace shared helper semantics, not just call sites.

**ND-5 — Swama's first SSE chunk carries no content** (role-only `delta`), invalidating "first chunk = first token" timing. Root cause: **confirmed** via live capture. Resolution: stamp on first non-empty content (AN-3). Earlier detection: protocol-level fixtures in tests (now present pattern).

**ND-6 — Prompt estimate dropped the current user turn** due to same-`Date.now` createdAt ordering (`<` vs `<=` + identity). Root cause: **confirmed** by code analysis. Resolution: `promptCharacterCount(for:)` (AN-4). Earlier detection: unit tests for estimate scope (now present).

**ND-7 — Apple provider metrics are self-referential** (rates measured the app's own 10 ms chunk simulation). Resolution: footer gating + `(est.)` labeling (AN-6) — a *workaround*, not a fix (§14).

**ND-8 — Internal documents were committed before a docs policy existed**, requiring untracking + a squash-merge strategy to keep them out of `main` history. Resolution: gitignore policy + squash merge (D-4). Earlier detection: decide documentation policy at project setup.

**ND-9 — Stale DerivedData rewrote tracked files.** Expectation: builds don't modify tracked files. Actual: reusing a pre-pin DerivedData caused xcodebuild to rewrite `Package.resolved` (re-adding `"branch"` fields) and drop the scheme's `<Testables>` block in the working tree. Root cause: **confirmed** — stale resolution state; proven by fresh-DerivedData resolve leaving the committed lockfile untouched. Resolution: restored files; verification builds use clean DerivedData. Earlier detection: `git status` gate after verification builds (see §13).

**ND-10 — Environment limitations:** simulator runtime/SDK mismatch initially blocked `actool` and destination discovery (resolved after the 26.5 runtime was installed); WebSearch/WebFetch unavailable (search backend failure; claude.ai unreachable) — `curl` via Bash used as fallback (this is how oMLX facts were verified against `jundot/omlx`). Root cause: **confirmed environment**; documented as constraints, not repo defects.

**ND-11 — F-25 boundary mis-scoped.** Expectation: `@MainActor` annotation fixes F-25. Actual (user review): store isolation ≠ model-ownership correction; live `PersistentModel`s crossing the actor boundary remain illegal until the ownership refactor. The audit **understated** the fix. Resolution: F-25 split into Part A/Part B; deferred to the correct phases.

## 8. Decisions and trade-offs

- **D-1 — Target architecture: main-actor SwiftData ownership** (documented in `CONCURRENCY_WARNING_AUDIT.md`, internal). Context: F-07-class races from a single actor-owned context mutated on the MainActor. Decision: app-owned `ModelContainer`, `mainContext` as the sole live-model context, `@MainActor` stores, DTOs across provider boundaries. Alternatives considered (evidenced): actor + DTO/PersistentIdentifier boundaries — rejected as ~3× churn with degraded SwiftUI observation for this codebase. Consequences: gates Swift 6 mode; requires F-03 first. Reversibility: moderate. **ADR recommended: yes** (architecturally significant, cross-cutting, long-lived).
- **D-2 — Preserve UserDefaults keys under UI relabel.** Context: OpenAI-compatible relabel. Decision: `swamaUri`/`swamaApiKey` keys and internal type names unchanged; only user-facing labels changed. Benefits: zero user-facing regression; migration-free. Reversible: yes. ADR: not needed.
- **D-3 — Squash-merge remediation branch** to keep internal documents out of `main` history. Benefits: policy compliance without history rewriting/force-push. Trade-off: granular commit history not preserved on `main` (recoverable only from dangling objects temporarily). ADR: not needed (process).
- **D-4 — Repository documentation policy: code + public release documents only; internal audit/process/AI documents gitignored.** Consequences: audit documents are cited but untracked; future reports under `docs/development-reports/` ARE tracked (public-safe by construction). ADR: not needed, but recorded here as the policy source of truth.
- **D-5 — Provider naming scheme:** "1. Ollama API" (native), "2. OpenAI API" (any OpenAI-compatible server; oMLX/Swama endorsed), "A:" Apple. Long-lived, user-facing, cross-cutting (UI, README, future providers). **ADR recommended: yes.**
- **D-6 — v1.1 / build 5** for this release (minor bump: features + P0 fix). ADR: not needed.
- **D-7 — Future full OpenAI rename: storage-compatible `Codable` (decode-both) rather than schema migration** (planned in `REFACTOR_OPENAI_API_PLAN.md`, internal; not implemented). ADR recommended when executed.

## 9. Verification performed

**Performed during report generation (2026-08-02):**

| Check | Command or method | Result | Evidence/notes |
|-------|-------------------|--------|----------------|
| macOS unit tests | `xcodebuild test -scheme Molten -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` (fresh DerivedData `/tmp/dd-report`) | **Passed** — 28 executed, 0 failures | `/tmp/report_test_mac.log` |
| macOS Release build | `xcodebuild build -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | **Passed** | product Info.plist = 1.1 (5); `PrivacyInfo.xcprivacy` present |
| Git evidence | `git log`, `git diff --stat af7ba46 a9cc893`, `git diff --name-status`, model/plist untouched check | Verified | 32 files, +1580/−364; `Molten/SwiftData/` empty diff |
| PR record | `gh pr view 1` | MERGED, mergeCommit `d4e75ed…`, 2026-08-01T18:55:25Z | |
| Repo metadata | `gh repo view` | description + 16 topics verified | |
| Source spot-checks | grep: half-open predicate, `onTermination` (3 services), `Usage` fields, footer gating, version | All present | |

**Performed earlier in the milestone (cited evidence):**

| Check | Result | Evidence/notes |
|-------|--------|----------------|
| iOS Simulator tests (28/28) | Passed | during implementation, iPhone 17 / iOS 26.5 |
| iOS Simulator + macOS Debug/Release builds | Passed | during implementation, per-commit |
| Unsigned archive inspection (Release, generic iOS) | Passed | no `*Tests.xctest`; manifest + usage descriptions present |
| Warning fingerprint diffs per change | No new/removed fingerprints | text-level, path-normalized, line-independent |
| Lockfile stability | Clean fresh-DerivedData resolve leaves committed `Package.resolved` untouched | demonstrated after ND-9 |
| Live backend validation (curl) | Ollama `/api/tags`+`/api/chat` streaming; Swama `/v1/models`+SSE `/v1/chat/completions` terminating `[DONE]` | during milestone |

**Not run / blocked / requires manual verification:** on-device LAN permission flow (F-11), live Stop behavior (F-05), default-model relaunch (O-02), token-auth flows (F-44/F-48), UI tests (none exist), lint/static analysis (none configured), v1.1 tag/release (not created).

## 10. Regressions and compatibility assessment

| Area | Assessment |
|------|------------|
| Existing-user data compatibility | **Verified** — SwiftData models unchanged in range (`Molten/SwiftData/` diff empty); no migration needed |
| Persistence/migration risk | Not verified for *future* changes — F-03 (no versioned schema) remains the top risk; this milestone added none |
| API compatibility (providers) | **Verified** — wire formats unchanged; `Usage` additions are optional-field decodes |
| Authentication/Keychain | N/A (no Keychain); tokens remain in UserDefaults (F-09 deferred) — behavior unchanged, risk documented |
| Purchases/subscriptions | Not applicable |
| Notifications/deep links | Not applicable |
| Supported OS versions | **Verified** unchanged (26.0/26.0); README corrected to match (documentation-only fix) |
| Accessibility impact | Not verified — no a11y work done; no regressions expected (label-less state unchanged) |
| Performance impact | **Verified** directionally positive — single prompt per turn (F-19) reduces server work; no new per-frame work; SSE internals unchanged |
| Release configuration | **Verified** — version 1.1/5 in product; manifest + usage description in archive; ATS unchanged |

## 11. What went well

- **Commit-per-finding discipline** — 20 granular commits each referencing finding IDs (`git log af7ba46..ccc046b`); enabled precise review and clean cherry-pickable history pre-squash.
- **Test-first extraction seams** — pure internal statics (`computeAnalytics`, `usageFromOllama`, `messageHistory`, `constructPrompt`, `makeRequest`, `promptCharacterCount`) yielded 28 deterministic tests with no live servers (evidence: `MoltenTests/` suites; all green at report time).
- **Warning-fingerprint methodology** — text-level, path-normalized, line-independent comparison made "zero new warnings" provable across every change set (evidence: per-change fingerprint diffs; identical sets before/after).
- **Review feedback loop** — external review (`IOS_REMEDIATION_PHASE2a.md`) caught the F-25 boundary, the docs policy, and an over-absolute timeout claim before merge; all three were incorporated.
- **Live protocol capture before/after changes** — Swama SSE captures informed AN-3 (role-only first chunk) and the `Usage` field set directly from observed wire data.
- **Correctness-before-metrics sequencing** — fixing F-19 before wiring server statistics avoided shipping metrics that would have exposed the duplicate prompt (ND-3).

## 12. What could be improved

- **The initial audit missed an entire user-visible surface** (analytics accuracy, ND-2) and understated three findings (F-19 priority, F-25 boundary, F-03 adjacency) — audit scope and method, not implementation, was the gap.
- **No documentation policy at project start** — internal docs were committed then untracked (ND-8); avoidable with a day-one policy.
- **Dependency drift was flagged but not demonstrated until it broke** — the audit identified the risk (F-18) but the baseline rebuild that proved it came later; the audit method should include the proof.
- **Verification builds mutated tracked files via stale DerivedData** (ND-9) — no post-build `git status` gate existed.
- **Device verification deferred past merge** by product decision — accepted risk, but the checklist items remain open and should gate the App Store submission even though they no longer gate the merge.
- **No CI** — all verification remains manual/ad hoc (F-51); every guarantee in this report decays silently without automation.

## 13. Lessons and preventive actions

| Lesson | Evidence | Future action | Enforcement point | Priority | Status |
|--------|----------|---------------|---------------|----------|--------|
| Audits must review user-visible metric accuracy, not just features | ND-2 (Ollama analytics fabricated) | Add a "data-accuracy pass" to audit prompts: for every displayed metric, trace source → mapping → formula → display and classify server-reported vs estimated | planning (audit prompt) | High | Open |
| Audit risk findings should include a live demonstration where cheap | ND-1 (drift broke baseline later) | Baseline clean rebuild + clean resolution as mandatory audit steps | planning (audit prompt) | High | Open (adopted in concurrency audit) |
| Dependency lockfiles must be committed for reproducible products | ND-1, F-18 | Keep `Package.resolved` tracked; CI fails on dirty resolution | CI | High | Partial (tracked; CI missing) |
| Correctness findings must be dependency-analyzed against metric sources before sequencing | ND-3 (F-19 ↔ analytics) | Planning step: map findings to shared data flows; fix upstream correctness before metric wiring | planning | Medium | Open |
| Shared helpers need semantic review, not call-site review | ND-4 (`handleError` early return) | Audits to document helper preconditions/side effects; tests for shared error paths | review + automated test | Medium | Open |
| Verification builds must not mutate the working tree | ND-9 (stale DerivedData rewrote tracked files) | Use clean DerivedData for verification; `git status` must be clean after any build step in verification scripts | CI + manual QA | Medium | Open |
| Provider wire formats should be fixture-tested from observed captures | ND-5 (role-only first chunk) | Store captured SSE/JSON fixtures as test inputs for every provider mapping | automated test | Medium | Open |
| Documentation policy must exist before the first commit | ND-8 (docs untracking + squash) | Decide public-vs-internal doc policy at project setup; gitignore internal docs immediately | planning + release checklist | Medium | Done (D-4) |
| Test seams as pure statics beat DI for this codebase's testability | 28 tests via 6 extracted statics | Keep the pattern; apply to remaining providers/stores in C2/C3 | architecture documentation | Low | Done (pattern established) |

## 14. Technical debt and newly discovered work

| Item | Why it matters | Evidence | Priority | Next action | Blocks features? |
|------|----------------|----------|----------|-------------|------------------|
| F-03 versioned SwiftData schema + fixture stores | Any future model change risks launch failures for existing installs | audit; `SwiftDataService` fatalError on container failure | **High** | Next milestone (§16) | **Yes — blocks any persistence-touching feature** |
| F-06/F-07/F-23/F-24/F-45/F-46 concurrency | Data races; dead reachability timer after backoff | audit; warning baseline | High | After F-03; TSan repro first | No, but degrades reliability |
| F-09 tokens in UserDefaults | Secrets in plaintext backups/prefs | audit | High | Keychain copy-then-delete migration | No |
| F-25 Part A/B | Off-main Observation publication; live models crossing actors | audit + review | Medium | C2 (A) / ownership refactor (B) | No |
| Accessibility (F-13/F-14/F-31/F-32/F-33) | VoiceOver unusable; no Dynamic Type | audit | Medium | Accessibility milestone | No |
| C1 mechanical warning cleanup | 58/59 warnings, 46/43 Swift-6-in-waiting | concurrency audit | Medium | `fix/ios-audit-warning-cleanup` branch | No |
| Full OpenAI rename refactor | Completes the relabel in code | `REFACTOR_OPENAI_API_PLAN.md` | Low-Medium | Awaiting naming/keys/timing decisions | No |
| Analytics: image-prompt undercount, Apple rates are simulated | Metric honesty gaps (labeled in UI) | AN-4, AN-6 | Low | Document or model-specific tokenization later | No |
| v1.1 tag + GitHub Release not created | Release process incomplete | `git tag -l` = v1.0.1 only | Medium | Draft release notes; tag; release | No |
| Device verification checklist (F-11 prompt, F-05 live stop, O-02, F-44/F-48 auth) | Merge-gate items accepted as risk | PR #1 checklist | High (pre-submission) | Run before App Store submission | No |
| Conversation export file at repo root | Untracked artifact; no ignore pattern | `git status` at report time | Low | Ignore or move; decide policy | No |
| No CI | All guarantees decay silently | F-51 | Medium-High | After F-03 | No |

## 15. Known limitations and unresolved questions

- **On-device behavior unverified:** F-11 LAN prompt/connection, F-05 live cancellation (including whether cancellation propagates into `session.respond(to:)` for the Apple provider), O-02 relaunch restore, F-44/F-48 authenticated flows.
- **Forced-failure tests missing:** F-20 and the day-delete error path lack tests that force `SwiftDataService` to throw — requires a persistence seam (planned with F-03/ownership work); until then these paths are verified by inspection only.
- **Granular branch history is dangling:** the 20-commit chain (`af7ba46..ccc046b`) is recoverable now but the branch ref is deleted; a future `git gc` may make it unreachable. Cited in this report while available.
- **Audit documents are untracked:** finding IDs referenced here (F-*, O-*, AN-*) resolve only to on-disk internal documents, not to the committed tree.
- **Web tooling unavailable:** WebSearch backend failing and WebFetch blocked in this environment; external facts (oMLX details) were verified via `curl` against `raw.githubusercontent.com`/GitHub API — reliable but not reproducible from this environment's native tools.
- **No lint/static-analysis baseline** exists; warning counts come from xcodebuild diagnostics only.

## 16. Recommended next milestone

**Objective:** Persistence safety foundation (F-03) — make future schema changes safe for existing installs.

**Included work:**
- `VersionedSchema` V1 capturing the currently shipped schema (verbatim — no property changes).
- `SchemaMigrationPlan` wiring into `SwiftDataService`'s container construction.
- Fixture-store compatibility tests: build a store with V1 data, open under the new code path, assert data intact.
- Graceful startup-failure behavior replacing `fatalError` (quarantine/rename + notify, or in-memory fallback with user-visible error).

**Explicitly excluded:** model property/relationship changes; the main-actor ownership refactor (separate branch, later); C1 warning cleanup; any F-25 Part B work; features.

**Entry criteria:** v1.1 merged (done); this report accepted.

**Completion criteria:** fixture store opens and queries under the new container path; simulated corruption boots without crashing; existing 28 tests + new fixture tests green on macOS + iOS Simulator; zero new warning fingerprints.

**Required verification:** as completion criteria, plus an installed-app upgrade smoke test (build old → create data → build new → data intact).

**Main risks:** SwiftData migration behavior differences across OS point releases; fixture creation must match the *actual* shipped schema encoding (enum storage format should be pinned by a test before any rename work begins).

## 17. Handover summary

- **Current stable state:** `main` @ `a9cc893` (pushed to `origin/main`); v1.1 code (1.1 / build 5); 28 tests green; working tree clean except one untracked conversation-export file.
- **Where to begin:** read this report §14–§16; then `IOS_TECHNICAL_AUDIT.md` (internal, on disk) for the full backlog; start the F-03 milestone on a new branch from `main`.
- **Files requiring care:** `Molten/Services/SwiftDataService.swift` (single actor-owned context; autosave off; fatalError on container failure), `Molten/Stores/ConversationStore.swift` (streaming + analytics; `@unchecked Sendable`), `Molten.xcodeproj/project.pbxproj` (hand-edited for test target/pins — keep edits surgical), `Package.resolved` (must stay committed and clean).
- **Commands to verify the baseline:**
  - `xcodebuild test -project Molten.xcodeproj -scheme Molten -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → expect 28/28.
  - `xcodebuild -resolvePackageDependencies -project Molten.xcodeproj -scheme Molten` (clean DerivedData) → expect `git status` clean afterward.
  - `git log --oneline af7ba46..HEAD` → expect `d4e75ed`, `a9cc893`.
- **Decisions that must be preserved:** UserDefaults keys unchanged (D-2); internal docs stay gitignored (D-4); provider naming scheme (D-5); lockfile stays committed; target architecture is main-actor ownership (D-1) — do not improvise a different persistence architecture.
- **Three highest-priority next actions:** (1) run the device verification checklist before App Store submission; (2) create the v1.1 tag + GitHub Release with release notes; (3) begin the F-03 persistence safety milestone.
