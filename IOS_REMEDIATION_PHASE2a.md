This is a good Phase 2 result: small commits, clean builds, increased tests, no new warnings, and no scope creep. I would approve it for review with two reporting corrections and one workflow change.

## Corrections to the report

### 1. F-20 should not yet be “Complete”

The implementation is present, but the test suite does not force the specific setup operations to throw:

- `updateConversation`;
- `createMessage`;
- `reloadConversation`.

The unknown-provider test verifies a terminal error state through a different path. It does not prove that the newly added `do/catch` handles a persistence setup failure correctly.

Use:

> **IMPLEMENTED — targeted failure-path verification pending**

The implementation can still merge. This is a testability gap, not necessarily a defect.

### 2. The day-delete error path has the same qualification

The report says selection is retained when deletion throws, but no test actually causes `deleteConversations` to throw.

Use:

> **IMPLEMENTED — success path and calendar behavior verified; injected deletion-failure test pending**

The DST coverage itself is fully verified.

A minimal throwing persistence seam can be introduced during the persistence architecture work. Do not distort `SwiftDataService` now merely to force this test.

### 3. Qualify the Swama streaming timeout claim

This sentence is too absolute:

> “streaming keeps progressing, so generation is not cut short”

A `URLRequest.timeoutInterval` is not the same as a guaranteed “stream-start-only” timeout. Its practical behavior can depend on the loading system and response activity. It is reasonable to configure it, but state:

> The stream request has an explicit 120-second request timeout; live behavior for long-running and stalled streams remains to be verified.

Also confirm the code did **not** set a short `URLSessionConfiguration.timeoutIntervalForResource`, which could impose a total lifetime limit on a legitimate generation.

## Branch/workflow recommendation

Do **not** begin C1 on `audit/ios-review`. The branch now contains two complete implementation phases and is already 12 commits beyond `main`. Continuing will make review and rollback harder.

### Recommended sequence

1. Save and commit the reports.
2. Push `audit/ios-review`.
3. Perform the manual stabilization checks.
4. Open a PR to `main`.
5. Merge after review.
6. Create `fix/ios-audit-warning-cleanup` from the updated `main`.
7. Run C1 there.

Commit the documentation separately:

```bash
git status --short

git add \
  CLAUDE.md \
  IOS_TECHNICAL_AUDIT.md \
  IOS_REMEDIATION_STATUS.md \
  CONCURRENCY_WARNING_AUDIT.md \
  IOS_REMEDIATION_PART2.md

git commit -m "docs: add iOS audit and remediation reports"
```

If the Phase 2 report is stored under another filename, include that too.

Then:

```bash
git push -u origin audit/ios-review
```

## Checks required before the PR is merged

### 1. Archive-content inspection

Ensure the test bundle is absent from an archive:

```bash
rm -rf /tmp/Molten.xcarchive

xcodebuild archive \
  -project Molten.xcodeproj \
  -scheme Molten \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Molten.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

Inspect:

```bash
find /tmp/Molten.xcarchive \
  \( -name 'MoltenTests.xctest' -o -name '*Tests.xctest' \) \
  -print
```

Expected: no output.

Also inspect:

```bash
find /tmp/Molten.xcarchive -name PrivacyInfo.xcprivacy -print

plutil -p \
  /tmp/Molten.xcarchive/Products/Applications/Molten.app/Info.plist
```

Confirm:

- app-level privacy manifest exists;
- `NSLocalNetworkUsageDescription` exists;
- versions and bundle identifier are correct;
- no test target ships.

### 2. Physical-iPhone LAN behavior

On a fresh install:

1. Configure a LAN IP, not `localhost`.
2. Confirm the Local Network prompt appears with the expected text.
3. Tap Allow and verify model discovery/chat.
4. Reinstall or reset Local Network permission.
5. Tap Don’t Allow and document the app’s error UX.
6. Re-enable access under Settings and verify recovery without reinstalling.

### 3. Live cancellation

For Swama:

- start a long generation;
- tap Stop before completion;
- confirm UI tokens stop;
- confirm the server observes disconnection/cancellation;
- repeat several times;
- verify no orphan requests remain.

For Apple Foundation Models, distinguish two cases:

- Stop while `session.respond(to:)` is still generating;
- Stop while Molten is emitting simulated chunks from an already completed response.

The second should stop immediately. The first verifies whether cancellation actually propagates into the Foundation Models operation.

### 4. Phase 2 smoke tests

Before merging:

- authenticated Ollama using only the saved token;
- custom Ollama URL with token;
- default localhost with token;
- Settings default-model selection → terminate app → relaunch;
- two-turn Apple conversation referring to the first turn;
- slow but active Swama stream longer than two minutes, if practical.

## Merge recommendation

After those checks:

> **Merge-ready:** yes, assuming the archive, LAN permission, and cancellation checks pass.  
> **Release-ready:** not yet; the known persistence, concurrency, secrets, and accessibility backlog remains.

## After merge

```bash
git switch main
git pull --ff-only
git switch -c fix/ios-audit-warning-cleanup
```

Then run C1. After C1, do not jump directly into the main-context refactor. Complete F-03/schema versioning and fixture tests on its own branch first, merge that independently, and only then begin the SwiftData ownership change.