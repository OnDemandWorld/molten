# What's New in Molten 2.0.1

A small bug-fix release ahead of the next major version.

## Fixes

- **Knowledge document counts now update immediately.** After adding or
  removing a document in a knowledge base, the count in the sidebar
  refreshes as soon as you close the base — it no longer stays stale
  (e.g. showing 4 documents after you deleted one of 4).
- **Smoother adding/removing of files.** Importing large documents and
  removing files (including coordinated iCloud deletes) now run off the
  main thread, so the UI no longer freezes during these operations.
- **More accurate Apple Foundation Models status.** The app now reports
  the on-device model as available only when Apple Intelligence is
  actually ready, instead of always showing it as reachable.

## Under the hood

- File listing, importing, and deletion in the Knowledge detail view
  moved to background tasks with results marshalled back to the UI.
- Added regression tests for the import limit and file-listing helpers.
- Full suite green on macOS; iOS build green.

---

**Requirements**: macOS 26.0+, iOS 26.0+, iPadOS 26.0+.
**Privacy**: unchanged — no data collected; inference on-device,
Knowledge syncs through your own iCloud.
