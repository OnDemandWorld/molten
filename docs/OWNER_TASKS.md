# Molten 2.0 — Owner task list (step by step)

Everything code-side is done (PRs #2–#11). Work through these in order.
Each step says exactly where to click, what to enter, and what to tell
Claude afterwards. Estimated total: ~1–2 hours plus Apple review time.

---

## Step 0 — Merge the PRs into `develop` (5 min)

The work is stacked: #2 → #3 → #4 → #5 → #6 → #7 → #8 → #9 → #10 → #11.
Merge them **in that order** (each targets `develop`).

**Option A — GitHub web:** open each PR, click "Merge pull request" →
"Confirm merge", in order #2, #3, …, #11. If a PR shows conflicts because
its parent just merged, click "Update branch" first.

**Option B — terminal (or tell Claude "merge the PRs"):**
```bash
for n in 2 3 4 5 6 7 8 9 10 11; do gh pr merge $n --merge; done
git checkout develop && git pull
```

After merging, `develop` contains all of 2.0. `main` stays at the shipped
1.1 until release (Step 6).

---

## Step 1 — Find the highest 1.x iOS build number (2 min)

**Why:** Early Supporter detection on iOS compares the original build number
against a cutoff. It's fail-closed until set, so no iOS buyer gets Plus
until this is done.

1. Go to https://appstoreconnect.apple.com → **My Apps** → **Molten**.
2. Left sidebar: **TestFlight** (or **App Store** → **Builds** section).
3. Look at every build ever uploaded for 1.x (versions 1.0, 1.0.1, 1.1).
   Note the **build number** in parentheses, e.g. "1.1 (5)".
4. Find the **largest** build number across all 1.x versions.

**Tell Claude:** "the highest 1.x build was N".
Claude will set `iosCutoffBuild = N + 1` (or higher) in
`EarlySupporterDetector.swift`, commit, and push. Every 2.0 build must be
numerically greater — 2.0 currently builds as **6**, so if N ≥ 6, tell
Claude and the 2.0 build number will be bumped instead.

---

## Step 2 — Create the in-app purchases in App Store Connect (20 min)

**Why:** the paywall sells these. The local `Molten.storekit` mirrors them
for development; ASC needs the real ones.

1. ASC → **My Apps** → **Molten** → left sidebar **Monetization** →
   **Subscriptions**.
2. **Create a subscription group:**
   - Reference name: `Molten Membership`
   - Group name (localization, en-US): `Molten Membership`
3. **Inside the group, create subscription #1 (Plus Monthly):**
   - Reference name: `Plus Monthly`
   - Product ID: `molten.plus.monthly`  ← must match exactly
   - Subscription period: **1 month**
   - Price: **US$2.99** (let ASC generate other storefronts; check HK)
   - Localization (en-US): display name `Plus Monthly`, description
     `Knowledge bases on all your devices.`
   - **Level: 2** (leave level 1 reserved for Pro — do NOT create Pro)
   - No introductory offer on monthly.
4. **Create subscription #2 (Plus Yearly):**
   - Reference name: `Plus Yearly`
   - Product ID: `molten.plus.yearly`
   - Period: **1 year**, price **US$19.99**
   - Localization: `Plus Yearly` / `Knowledge bases on all your devices.
     1-week free trial.`
   - **Level: 2** (same level as monthly — they're the same tier)
   - **Introductory offer:** type **Free trial**, duration **1 week**.
5. Left sidebar **Monetization** → **In-App Purchases** → **+**:
   - Type: **Non-Consumable**
   - Reference name: `Plus Lifetime`
   - Product ID: `molten.plus.lifetime`
   - Price: **US$49.99**
   - Localization: `Plus Lifetime` / `Molten Plus forever. One purchase,
     all your devices.`
6. For each product: fill the **App Review Information** screenshot field
   (a screenshot of the paywall is enough — run the app, Knowledge ▸ add
   an 11th document to show it) and set status to **Ready to Submit**.
7. **Family Sharing:** leave OFF for Plus (PRD §14: off at launch).

**Tell Claude:** "products created" (or paste any product-ID mismatch).

---

## Step 3 — Archive and upload the 2.0 build to TestFlight (15 min)

Do this AFTER Steps 0–1 (so the cutoff is in the build).

1. `git checkout develop && git pull` (or tell Claude to prepare the
   release branch).
2. Open `Molten.xcodeproj` in Xcode.
3. Top toolbar destination: **Any iOS Device (arm64)**.
4. Menu **Product ▸ Archive**. Wait for the build.
5. Organizer opens → select the new archive → **Distribute App** →
   **TestFlight & App Store** → **Upload** → accept defaults → wait.
6. ASC → **TestFlight**: the build appears after processing (5–30 min).
   - If it asks about export compliance: Molten uses only standard HTTPS
     (URLSession) → answer **No** to "uses non-exempt encryption" (or
     qualify for the exemption — standard HTTPS qualifies).
7. Add yourself as an internal tester; install TestFlight on the iPhone.
   **Do NOT install 2.0 yet** — Step 5 needs a 1.1 install first.

**Tell Claude:** "2.0 build uploaded" (note the build number shown).

---

## Step 4 — Two-device iCloud Knowledge pass (A2/A13) (20 min)

Verifies: one shared folder, Mac processes once, iPhone searches without
processing.

**Setup:** Mac and iPhone signed into the **same iCloud account**, iCloud
Drive ON, iCloud Keychain ON (Settings ▸ your name ▸ iCloud).

1. On the **Mac**: run Molten 2.0 (from Xcode or the TestFlight build).
2. In the sidebar **Knowledge** section: create a base, e.g. `Test`.
   The shared folder appears in Finder ▸ iCloud Drive ▸ **Molten** ▸
   `Test`. (First run: the ~480MB embedding model downloads once.)
3. Drop 2–3 PDFs/text files into that folder (Finder drag or "Add files…").
4. Click **Process now** if it doesn't start. Wait for status **Indexed**
   (watch the per-file status in the base detail view).
5. On the **iPhone**: open Molten 2.0 (TestFlight). Within ~5 minutes the
   `Test` base should appear in the Knowledge sidebar with the same
   document count. **Check the iPhone did no processing:** its status
   should go straight to searchable (it only downloads the finished index
   files; the model download may happen for query embedding, but no
   extraction/OCR of the documents).
6. On iPhone: open a chat, attach the `Test` base (Knowledge ▸ base ▸
   "Attach to chat", or type `@Test your question`), ask something whose
   answer is in a document. Verify: answer cites `[1]`-style chips; tap a
   chip → the source file opens.
7. **Rename test (A5):** rename one file in Finder on the Mac. Within a
   few minutes the iPhone still finds it; no re-indexing happens on
   either device (status stays Indexed).
8. **Airplane test (A7):** iPhone airplane mode ON, Wi-Fi OFF → keyword
   search in the Knowledge view still returns passages (local index).

**Tell Claude:** the results of 5/6/7/8 (pass/fail + anything odd).

---

## Step 5 — Early Supporter upgrade test (A8/A9) (15 min)

Verifies: a real 1.x buyer gets Plus forever, automatically.

1. On the iPhone, install **Molten 1.1 from the App Store** (the live
   paid version — use the account that bought it, or any account; the
   detection reads the original purchase).
2. Open 1.1, create a conversation or two (so there's data to migrate).
3. Install the **2.0 TestFlight build over it** (TestFlight ▸ Molten ▸
   Update/Install). This is an upgrade, not a fresh install.
4. Open 2.0. Expected:
   - One-time **"Thank you, Early Supporter"** sheet with the Plus-forever
     text.
   - Settings ▸ Subscription shows **"Molten Plus — Early Supporter
     (lifetime)"**.
   - No paywall anywhere; Knowledge allows >1 base / >10 docs / iCloud.
   - The 1.1 conversations are intact (migration, A10).
5. On the **Mac** (same iCloud account): open 2.0 → Settings ▸
   Subscription should also show Plus — the grant syncs via iCloud
   Keychain (may take a minute; M4/M11).
6. **Sandbox sanity:** a fresh install on a device that never bought 1.x
   must NOT get the thank-you sheet (Free tier).

**Tell Claude:** pass/fail for each of 4/5/6.

---

## Step 6 — Submission and release (M8) (30 min + review time)

1. ASC → **App Store** tab → prepare the 2.0 version:
   - **What's New:** copy from `docs/APP_STORE_v2.md` (includes the Early
     Supporter promise).
   - **Description:** update per `docs/APP_STORE_v2.md` (privacy wording:
     "on your devices and your own iCloud — no Molten servers, no
     account").
   - **Screenshots:** Knowledge first (shared folder → cited answer on
     iPhone → Mac processing), then search/export, context meter, chat.
   - **Keywords/privacy:** privacy label stays **Data Not Collected**.
2. **Pricing and Availability:**
   - **Price: Free** (set it now; it takes effect when you release).
   - **Apple Vision Pro availability: OFF** (PL4 — the listing currently
     shows Vision compatibility).
3. **App Review Information:** paste the review note from
   `docs/APP_STORE_v2.md` (freemium move, where to find the paywall:
   Knowledge ▸ add an 11th document; Early Supporters auto-granted).
4. Select the uploaded 2.0 build (Step 3).
5. **Version release: manually release** (not automatic).
6. **Submit for Review.**
7. After approval: confirm the **Free price is live**, then click
   **Release**.
8. Tell Claude "released" → Claude merges `develop` → `main`, tags
   `v2.0`, and updates the README/listing notes.

---

## Quick reference — who does what

| Step | Owner | Claude |
|------|-------|--------|
| 0 merge PRs | click merge (or ask Claude) | can run the merges if asked |
| 1 build history | read ASC, report number | sets iosCutoffBuild, commits |
| 2 products | create in ASC | — |
| 3 archive/upload | Xcode Organizer | can prep the branch |
| 4 two-device test | run on devices | fixes anything found |
| 5 upgrade test | run on devices | fixes anything found |
| 6 release | ASC submission | merges main + tags after release |

If any step fails or looks different from the description, stop and tell
Claude what you see — don't guess.
