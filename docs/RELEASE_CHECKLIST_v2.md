# Molten 2.0 — Release checklist (owner actions, PRD §11)

Agent-completed: M0–M7 code, tests, materials (see PRs #2–#9 and
docs/DEVIATIONS.md for the environment-blocked verifications).

## Before TestFlight (M7)

- [ ] Open Molten.xcodeproj in Xcode, signed in as edward@ondemandworld.com.
      Let automatic signing register the iCloud container
      `iCloud.DVGF44TKAX.com.ondemandworld.molten` and create profiles
      (unblocks macOS/iOS signed builds).
- [ ] App Store Connect ▸ build history: confirm the highest shipped 1.x iOS
      build; set `EarlySupporterDetector.iosCutoffBuild` above it (every 2.0
      build must be greater; current 2.0 build = 6).
- [ ] Run the gated test suites on a provisioned device:
      `build/session/SPIKE_ENABLED` → M1SpikeTests (Mac + iPhone, then
      `SPIKE_COMPARE` for K-E5 cosine > 0.999);
      `build/session/STOREKIT_FLOWS_ENABLED` → M2 StoreKit flows;
      `build/session/MOLTEN_PERF` → A1/A4 (record iPhone numbers).
- [ ] Two-device Knowledge test (A2/A13): base on Mac → PDF → searchable on
      iPhone within 5 min with zero iPhone processing; Share-less add via
      Files app.
- [ ] Kill/resume background processing test (A3).
- [ ] Upgrade a production 1.1 install to the beta (§11.1): thank-you sheet,
      Plus on every device via Keychain, no paywall (A8/A9).
- [ ] Create products in App Store Connect: group "Molten Membership",
      Plus level 2 (molten.plus.monthly $2.99, molten.plus.yearly $19.99 +
      1-week trial), molten.plus.lifetime $49.99 non-consumable. Pro level 1
      reserved, NOT created.

## Submission (M8)

- [ ] Pricing & Availability: turn OFF Apple Vision Pro (PL4).
- [ ] Set price to Free; submit with MANUAL release (§11.3–4).
- [ ] Review note: see docs/APP_STORE_v2.md.
- [ ] After approval: confirm Free price is live, then release.
- [ ] Update listing: description, screenshots (Knowledge first), What's New
      with the Early Supporter promise, privacy wording (P3).
- [ ] README "Supporting Molten" section (already added in this branch).

## Post-release

- [ ] Monitor App Store Connect subscription analytics (no in-app analytics,
      M14).
- [ ] Plan 2.1 per PRD §13 (chat sync, personas, compact, Index encryption).
