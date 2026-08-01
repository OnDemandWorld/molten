This is a strong audit, and it resolves the warning-count question: the stabilization tranche introduced **no net-new warnings**. The comparison methodology is credible, and the dependency-drift caveat is especially useful.

I agree with the main architectural conclusion—**main-actor ownership of UI-visible SwiftData models is the better fit**. Apple explicitly documents `ModelContainer.mainContext` as bound to the app’s main actor, which aligns with Molten’s existing SwiftUI model usage. [Apple: `ModelContainer.mainContext`](https://developer.apple.com/documentation/swiftdata/modelcontainer/maincontext)

I would approve the report with a few changes to sequencing and claims.

## Recommended report adjustments

### 1. Avoid saying the KeyPath warnings are definitively unfixable

Use:

> The KeyPath/Predicate warnings appear to be SwiftData/toolchain diagnostics for which no safe application-level fix has been identified.

That is stronger than speculation but avoids asserting that only Apple can solve them before performing the proposed Swift 6 spike. Apple’s forums contain reports of the same `#Predicate`/`SortDescriptor` behavior, but the actual result may depend on isolation and compiler version.

The main-context refactor could change whether some diagnostics occur. Re-measure afterward before creating a permanent allow-list.

### 2. Don’t combine F-03 and the context-ownership refactor

Both are high-impact changes. Combining them would make persistence regressions difficult to diagnose.

Use this sequence:

1. Introduce `VersionedSchema` representing the current shipped schema.
2. Add fixture-store compatibility tests.
3. Make no model-property or relationship changes.
4. Merge and verify.
5. In a separate branch, change context ownership to `mainContext`.
6. Again verify the same fixture stores and existing installation data.

The context-ownership change should not require a data migration, but F-03 should be completed first as a safety net—not in the same commit.

### 3. Move F-25 out of the simple store-isolation batch

Annotating `CompletionsStore` with `@MainActor` fixes off-main Observation publication, but it does not fix this boundary:

```text
SwiftDataService actor
    → [CompletionInstructionSD]
    → @MainActor CompletionsStore
```

That remains illegal because `CompletionInstructionSD` is a live non-Sendable `PersistentModel`.

Therefore classify F-25 as:

- **Part A:** store/main-actor isolation;
- **Part B:** persistent-model ownership correction.

It is only fully resolved after the main-context refactor.

### 4. Don’t promise an exact warning reduction for C1

Some fixes can move diagnostics to call sites. For example, marking a callback `@Sendable` may reveal that its captured values are not Sendable.

The C1 acceptance criterion should be:

> Every targeted warning is either removed without replacement or documented as requiring a wider isolation change; no new warning category or unsafe annotation is introduced.

### 5. Keep the warning baseline small and temporary

A 55-fingerprint permanent allow-list is cumbersome and can normalize technical debt. Initially store:

- warning counts by category;
- raw build logs as CI artifacts;
- a narrowly scoped allow-list only for confirmed toolchain diagnostics.

Once C1–C4 are complete, the allow-list should contain only generated/toolchain warnings.

---

# Recommended execution order

## Phase 1 — Manual stabilization checks

Before further refactoring:

1. Physical-iPhone Local Network prompt and LAN connection.
2. Live Stop behavior with Swama.
3. Live Stop behavior with Apple Foundation Models.
4. Unsigned archive inspection:
   - privacy manifest;
   - local-network description;
   - no `MoltenTests.xctest` in the archive.
5. Commit the three audit documents.

## Phase 2 — Remaining small correctness fixes

Do the prior Batch 1, but exclude F-25:

- day-delete error path;
- DST deletion test;
- F-20;
- F-26;
- F-42;
- F-44/F-48;
- O-02.

These provide more immediate user value than cosmetic warning cleanup.

## Phase 3 — C1 mechanical warnings

Then run the proposed C1 batch, with the adjusted acceptance criteria below.

## Phase 4 — Persistence safety foundation

Implement F-03 alone:

- current shipped schema represented as V1;
- migration plan;
- fixture store tests;
- graceful startup failure behavior;
- no model changes yet.

## Phase 5 — Main-actor SwiftData ownership

In a separate branch:

- app-owned `ModelContainer`;
- `mainContext` ownership;
- `@MainActor` stores;
- eliminate live persistent-model transfer across actors;
- remove or convert the actor service;
- TSan and fixture-store verification.

## Phase 6 — Timer/task isolation

Then address:

- F-06;
- F-23/F-24;
- F-45/F-46;
- F-39;
- remaining AppStore and task warnings.

---

# Revised C1 prompt

The report’s C1 prompt is usable, but I would replace it with this safer version:

```text
Implement Batch C1: isolated mechanical warning cleanup.

Repository:
- /Users/eplt/SCM/molten
- Expected working branch: create/use a dedicated branch such as
  fix/ios-audit-warning-cleanup
- Relevant report: CONCURRENCY_WARNING_AUDIT.md
- This batch must not change SwiftData ownership or store architecture.

In scope, and only in scope:

1. SplashSyntaxHighlighter+Extension.swift:
   deprecated Text concatenation.

2. SpeechRecogniser.swift:
   deprecated microphone-permission API.

3. HapticsService.swift:
   UIKit main-actor isolation.

4. Accessibility.swift:
   unreachable code and investigation of
   kAXTrustedCheckOptionPrompt concurrency diagnostics.

5. RecordingView.swift:
   callback isolation/sendability.

6. Binding+Extension.swift:
   callback/capture diagnostics, but only if the helper has active callers.

Do not implement any other audit finding.

Hard constraints
================

- Do not modify:
  - SwiftDataService;
  - SwiftData model declarations;
  - AppStore;
  - CompletionsStore;
  - ConversationStore;
  - LanguageModelStore;
  - provider behavior;
  - Package.resolved;
  - project settings;
  - deployment targets;
  - entitlements;
  - plists;
  - privacy manifests;
  - asset catalogs.

- Do not add:
  - @unchecked Sendable;
  - nonisolated(unsafe);
  - @preconcurrency merely to silence diagnostics;
  - unsafe global Sendable conformances;
  - warning-suppression flags;
  - compiler-version conditionals that merely hide warnings.

- Do not change SWIFT_VERSION or SWIFT_STRICT_CONCURRENCY.
- Do not add dependencies.
- Do not perform unrelated dead-code cleanup.
- Do not reformat unrelated files.
- Do not push, merge, rebase, amend, tag, or modify main.

Preflight
=========

Run and report:

1. pwd
2. git status --short
3. git branch --show-current
4. git rev-parse HEAD
5. git log -5 --oneline --decorate
6. git diff --check
7. xcodebuild -version
8. xcodebuild -project Molten.xcodeproj -scheme Molten -showBuildSettings |
   grep -E 'SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR'

Stop if:
- the repository path is unexpected;
- the working tree contains unexpected modifications;
- the branch is main;
- Package.resolved differs before implementation.

Before editing
==============

For each target warning:

1. Confirm the warning with a clean build.
2. Inspect all callers of the affected symbol.
3. Determine the actual isolation domain.
4. Prefer explicit actor isolation over Sendable suppression.
5. If the only apparent fix requires unsafe annotations or a wider
   architectural change, do not implement it; document and defer it.

A. Splash Text deprecation
==========================

- Inspect whether Text operands have independent styling.
- Replace deprecated `Text + Text` composition using the current supported
  Text interpolation/composition API.
- Preserve localization and styling behavior.
- Add no string flattening that loses attributed Text modifiers.
- Verify the deprecation warning disappears on macOS and iOS.

B. Speech permission API
========================

- Replace deprecated AVAudioSession.requestRecordPermission with the current
  AVAudioApplication permission API available at the deployment target.
- Preserve:
  - granted callback behavior;
  - denied callback behavior;
  - callback actor/thread expectations;
  - existing user-facing state.
- Explicitly hop to MainActor before mutating UI-observable state.
- Do not alter speech-recognition behavior beyond permission acquisition.

C. HapticsService isolation
===========================

- Inspect all call sites.
- Isolate UIKit feedback-generator creation and use to MainActor.
- Prefer annotating the service/type or relevant methods `@MainActor` when
  callers are UI actions.
- Update call sites with explicit `await MainActor.run` only where genuinely
  required.
- Do not use assumeIsolated.
- Confirm both iOS and macOS conditional compilation still succeeds.

D. Accessibility warning
=========================

- Remove only the proven unreachable block after the unconditional return.
- Investigate the kAXTrustedCheckOptionPrompt warning separately.
- Use the documented Accessibility API pattern if it compiles cleanly.
- Do not replace the imported constant with an undocumented magic string
  merely to silence the compiler.
- Do not add nonisolated(unsafe), @unchecked Sendable, or @preconcurrency.
- If no safe, documented application-level solution removes the warning,
  leave that warning unchanged and report it as deferred/toolchain-related.

E. RecordingView callback
==========================

- Determine whether onCompleteClosure is always invoked as a UI callback.
- If so, use an explicitly `@MainActor` callback type.
- Add `@Sendable` only if all call-site captures are genuinely Sendable.
- Do not add `@Sendable` merely to move warnings to call sites.
- Preserve callback ordering and behavior.

F. Binding extension
====================

- Find all active call sites, excluding comments and previews.
- If the helper has no active callers:
  - do not rewrite it in this batch;
  - report it as dead-code cleanup for F-56;
  - leave it unchanged unless explicit approval is given to delete it.
- If it has callers:
  - determine why its closure is inferred as @Sendable;
  - preserve Binding get/set behavior;
  - isolate the handler appropriately;
  - do not capture Binding in a concurrently executing closure unless the
    compiler can prove the isolation.

Commit structure
================

Use one small commit per independently reviewable warning group.

Before every commit:

- run the focused build;
- inspect git diff;
- run git diff --check;
- ensure only intended files are staged.

Do not commit a speculative change that merely transforms one warning into
another.

Verification
============

Use clean, separate DerivedData paths.

Run:

1. macOS Debug clean build
2. macOS Release clean build
3. iOS Simulator Debug clean build
4. iOS Simulator Release clean build
5. Unit tests on macOS
6. Unit tests on iOS Simulator

Use:
- project Molten.xcodeproj;
- scheme Molten;
- CODE_SIGNING_ALLOWED=NO;
- an installed explicit iOS Simulator destination.

Capture complete logs.

Compare against CONCURRENCY_WARNING_AUDIT.md and report:

- warning counts before and after by platform/configuration;
- each targeted warning removed;
- each targeted warning retained and why;
- new warning fingerprints;
- warnings moved to call sites;
- Swift 6 errors-in-waiting before and after;
- whether any unsafe annotation was introduced.

Acceptance criteria
===================

- Every implemented fix removes its targeted warning without creating a
  replacement warning or changing behavior.
- A target may be explicitly deferred if its only safe solution belongs to a
  wider architecture batch.
- No new warning category appears.
- No unsafe concurrency annotation is introduced.
- All Debug/Release builds succeed.
- All tests pass with nonzero test counts.
- Package.resolved remains unchanged.
- No out-of-scope file changes.

Do not require an exact total warning reduction in advance; calculate the
actual reduction from clean logs.

Final report
============

Report:

- starting branch and HEAD;
- commits created;
- files changed;
- warning-by-warning disposition;
- before/after warning matrix;
- build matrix;
- test counts;
- deferred warnings and rationale;
- confirmation that SwiftData/store architecture was untouched;
- Package.resolved status;
- final git status.

Stop after C1. Do not start store isolation, persistence ownership, Swift 6
migration, assets, accessibility UI work, or other audit batches.
```

## Bottom line

The stabilization branch remains valid: the warnings are pre-existing, and the comparison confirms that. But the project is not close to flipping `SWIFT_VERSION = 6` yet.

The best path is:

1. finish manual stabilization verification;
2. finish the small user-facing correctness batch, excluding F-25;
3. perform C1;
4. version the schema;
5. migrate SwiftData ownership to the main actor;
6. re-measure the KeyPath warnings before declaring them permanent toolchain blockers.