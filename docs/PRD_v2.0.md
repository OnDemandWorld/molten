# Molten 2.0 — Product Requirements (Reverse-Engineered)

> **What this document is.** Molten 2.0 shipped to the App Store on
> 2026-11-21 (version 2.0, build 10, tag `v2.0`). This is the PRD
> *reconstructed from the shipped code* — every requirement below is
> implemented and verified, not planned. Use it two ways:
>
> - **Planning**: the feature IDs, current constants, and explicit
>   non-goals mark exactly where 2.1+ extends.
> - **Marketing**: §9 distills each area into shipped, truthful claims —
>   every number here is real and test-covered.
>
> Sources: `main`/`develop` at `v2.0`, `RELEASE_NOTES_v2.0.md`,
> `ARCHITECTURE.md`, `docs/SPIKE.md`, `docs/DEVIATIONS.md`, test suite
> (133 tests).

---

## 1. Product definition

**Molten** is a native SwiftUI app for macOS, iOS and iPadOS: a
ChatGPT-style interface for **local LLMs** — Ollama, any
OpenAI-compatible server (oMLX, Swama, …), and Apple Foundation Models —
with **private, cited document chat** (Knowledge/RAG) that syncs across
devices through the user's own iCloud.

**Positioning:** "Local AI. On Your Terms." The only major local-AI chat
app that is (a) fully native on Mac + iPhone + iPad, (b) multi-backend,
and (c) puts RAG over your own documents on-device with citations —
with zero Molten servers and zero accounts.

**Principles (all enforced in code):**
1. Privacy by architecture — inference local; sync only via the user's
   own iCloud container; no telemetry (`ITSAppUsesNonExemptEncryption=0`,
   no third-party SDKs).
2. Works offline — everything but initial model download runs offline.
3. Native feel — SwiftUI everywhere, one codebase, platform-appropriate
   chrome.
4. Free app, paid value — paid Plus funds development; the app's core
   chat stays free forever; Early Supporters get Plus for life.

**Personas:**
- **Mac power user** (primary): runs Ollama/oMLX locally, wants a real
  native chat UI plus a floating quick-access panel.
- **Privacy-conscious professional**: contracts, notes, manuals — needs
  answers *from their own documents* with verifiable citations, never
  uploaded to a third-party cloud.
- **Multi-device user**: Mac + iPhone + iPad, expects the knowledge base
  to simply be there on every device.
- **Developer / tinkerer** (community): audits and forks the Apache-2.0
  source.

---

## 2. Entitlements & tiers (F-TIER)

| ID | Requirement | Shipped behavior |
|---|---|---|
| T1 | Two tiers | **Free** and **Plus** (`Entitlements.swift`: `Tier`, `Capability`) |
| T2 | Plus capabilities | `iCloudKnowledge`, `unlimitedKnowledge`, `ocr`, `priorityProcessing` |
| T3 | Purchase options | `molten.plus.monthly` US$2.99 · `molten.plus.yearly` US$19.99 with **1-week free trial** · `molten.plus.lifetime` US$49.99 (one non-consumable) |
| T4 | Paywall only on intent | Paywall appears **only** when the user hits a limit or taps Plan→upgrade — never at launch (M10). Tapping a limit opens the paywall (K-U5) |
| T5 | Paywall design | Native-styled designed wrapper (icon, headline "Your documents, on all your devices", feature list, best-value note, renewal disclosure, ODW.ai Terms/Privacy/House-Rules links) around the native `SubscriptionStoreView` + lifetime card; restore-purchases button visible |
| T6 | Graceful downgrade | If Plus lapses, nothing is deleted: existing knowledge stays searchable on each device; only processing/sync of new documents pauses (`EntitlementManager.refresh()` requires a future `expirationDate` to grant) |
| T7 | Settings ▸ Plan row | Tappable: Free → paywall; Plus → plan details (renewal date, Manage, Restore, Early-Supporter thank-you) (M13) |

**Early Supporter migration (F-ES):**
- ES1 — anyone whose **first Molten purchase predates 2.0** gets Plus
  forever, automatically, with no purchase or restore step.
- ES2 — detection: `AppTransaction.originalAppVersion` compared against
  cutoffs — macOS first marketing version ≥ "2.0" is *not* ES (string
  compare is numeric-component-wise, `VersionCompare`); iOS builds ≤ 6
  are ES (cutoff build **7**, owner-confirmed).
- ES3 — the grant is mirrored to a **synchronizable iCloud Keychain**
  item (`molten.entitlement/earlySupporter`), so a fresh install on any
  device sees it; works fully offline.
- ES4 — sandbox/Xcode builds never grant entitlement (receipt truth
  comes from the App Store); a DEBUG-only simulate toggle exists for QA.
- ES5 — Pro is explicitly reserved as a future separate tier; tier math
  already accounts for it.

---

## 3. Knowledge — the RAG subsystem (F-KNOW)

### 3.1 Organization & storage (K-S*, K-D*)

- S1 — one knowledge base = one folder under `Documents/` in the
  **shared iCloud container** `iCloud.DVGF44TKAX.com.ondemandworld.molten`
  (visible in Files/Finder as **Molten ▸ Documents ▸ <base>**); identical
  on-disk layout locally (`Application Support/Molten/LocalKnowledge`)
  when Free or iCloud unavailable — the app code never branches on
  location (K-S5).
- S2 — watched areas: `Documents/` (sources) and `Index/` (outputs,
  `.mkt`/`.mkv`); watchers via `NSMetadataQuery` + a full scan at launch.
- D1 — **content addressing**: outputs are keyed by SHA-256 of the
  source bytes. Renaming, moving, duplicating, or opening on another
  device never reprocesses (A5).
- D2 — `.mkt`: `MKT1` magic + LZFSE-compressed JSON (extracted text,
  chunk/char/page maps, model-independent). `.mkv`: `MKV1` + JSON header
  + Float16 embedding vectors in chunk order, one file per embedding
  profile. fp16 conversion is architecture-independent
  (`HalfFloat` bit codec — byte-identical on Intel and Apple Silicon).
- D3 — outputs are **write-once, never edited**; the `encryption` field
  is reserved (must be null in 2.0) for index encryption in 2.1 (P5).
- D4 — each device builds its own SQLite index (FTS5 + vectors) from
  `.mkt`/`.mkv` files; the database itself never syncs. Search never
  depends on iCloud download state (cached outputs ingest on arrival).
- D5 — base membership = local path→hash mapping (`filemap.json`, never
  synced); deletions propagate: vanished files are pruned, their index
  rows removed.

### 3.2 Processing pipeline (K-P*)

- P1 — pipeline: extract → chunk → embed → index → retrieve → compose.
- P2 — extraction: PDF (PDFKit, per-page), plain text/Markdown, RTF,
  HTML, DOCX, and images (PNG/JPEG/HEIC) via **Vision OCR** (Plus-only,
  real entitlement prefilter). Chunker: ~350-token target, 480-token
  hard cap, heading/paragraph-aware boundaries with char/page offsets.
- P3 — claims & leases: each (hash, stage) is claimed for 10 min,
  renewed every 60 s, 3 strikes → `.failed` with per-file retry — so no
  two devices process the same document and a crashed device doesn't
  wedge it.
- P4 — device roles & heartbeats: devices announce via heartbeats
  (15-min cadence); iPhone/iPad defer heavy processing to a fresh Mac
  ("Waiting for Mac"), or process per policy (`bothWhileCharging`,
  `alwaysBoth` — Settings ▸ Knowledge); "Process Now" overrides.
- P5 — iOS background continuation: `BGContinuedProcessingTask`
  (`…knowledge.processing`) keeps long jobs alive across app switches
  (K-P6 user-action scheduling).
- P6 — cellular courtesy: one-time ~**480 MB** embedding-model download
  asks confirmation on cellular and shows the size (K-E3).
- P10 — outputs no longer referenced by any document are deleted after
  a **7-day grace window**; deferred when the local mapping is
  incomplete (evicted iCloud files) so shared outputs are never lost.
- P11 — resume durability: interrupted work continues; completed stages
  are never repeated (test A3).

### 3.3 Embeddings (K-E*)

- E1 — **e5-small-v2** via MLXEmbedders on Apple Silicon; 384 dims, mean
  pooling with **position-based attention mask** (pad token is EOS), L2
  normalization; `passage:` / `query:` prefixes.
- E2 — profile + model revision are stamped into every `.mkv`; the index
  never mixes profiles or revisions (manifest gating, A6). Profile
  changes are handled by migration (K-E4).
- E5 — cross-device vector agreement verified on hardware: minimum
  cosine 0.9999985 (`docs/SPIKE.md`) — Mac and iPhone produce a common
  index space.

### 3.4 Retrieval & grounding (K-R*)

- R1 — attach a base per conversation: **"Use in Chat"** button (creates
  a chat if none open, lands you directly in it, shows the
  "Knowledge: <base>" chip with one-tap detach) or typing
  `@Base name …` in the composer.
- R2 — **hybrid search**: FTS5 BM25 top-20 + cosine (vDSP) top-20,
  merged by **reciprocal rank fusion (k=60)**. Without the embedding
  model (or offline), keyword-only — labeled, never broken (A11).
- R4 — context injection: top chunks within the model's context budget,
  numbered `[1] … [n]` with file name and page, plus a citation
  instruction; **Apple's on-device model gets at most 3 chunks** (4096-token
  window; grounding capped ~1536 tokens), other providers up to 8. AFM
  grounding is delivered as session **instructions** (followed
  reliably), not pasted transcript text.
- R5 — **citation chips** under each answer; tap opens the source file
  (Quick Look on iOS, default app on macOS). Citations persist with the
  message.
- R6 — direct passage lookup available to features without an LLM.
- R7 — retrieval is provider-independent: the same index serves any chat
  model; only the injected slice adapts to the window.

### 3.5 Knowledge UI (K-U*)

- U1 — sidebar list with per-base document count and a status
  vocabulary: *Indexed · Processing n/m · Text ready, semantic search
  pending · Waiting for Mac · Needs re-index · Error*.
- U2 — base detail: file list (evicted iCloud files shown under real
  names with iCloud badge), Add Files, Process Now, swipe/context-menu
  **Remove from base** with confirmation, Done, `⋯` menu, Use in Chat.
- U3 — Share extension "Add to Molten Knowledge" (iOS): share a file
  from any app → lands in a chosen base and gets processed like a drop.
- U4 — **free path**: "use a document once in this chat" (no indexing)
  available to everyone.
- U5 — Free limits enforced in UI with paywall on intent: **1 base,
  10 documents** (K-U5 via `KnowledgeLimits`).
- U6 — first-base onboarding sheet, incl. the privacy sentence (P2):
  files sync via your own iCloud; no Molten servers; ADP recommended.

---

## 4. Chat core (F-CHAT)

- C1 — three backends behind one protocol (`ModelProviderProtocol`:
  `reachable / getModels / chatStream`): **OllamaService** (native API,
  Combine→AsyncThrowingStream), **SwamaService** (OpenAI-compatible,
  hand-rolled SSE — works with oMLX, Swama, any `/v1/chat/completions`
  server), **AppleFoundationService** (FoundationModels on-device,
  simulated streaming). Provider-dispatched models shown with prefixes
  (`S: / O: / A:` per `ModelProvider.displayPrefix`).
- C2 — streaming pipeline: array-buffered chunks, 0.15 s throttled UI
  flushes, `generationTask` cancellation (Stop), partial analytics on
  stop; mid-stream conversation switching writes to the right message.
- C3 — system prompt injected on first turn; multi-turn history to all
  providers (including AFM, F-26).
- C4 — reachability polling with smart backoff: default localhost
  aggressive (30 s→300 s), user URLs moderate (10 s→60 s), 10 s result
  cache, 2 s timeouts, per-platform ping interval (macOS 15 s, iOS 30 s);
  an explicitly empty URL disables that provider without a network call.
- C5 — per-message analytics: server-reported usage wins; client-side
  estimates otherwise (honestly labeled); tokens/timing rates/throughput
  footer.
- C6 — vision: image input when the selected model supports it; images
  cached as data URLs (O(n) fix in history building).
- C7 — voice: speech-to-text input and read-aloud output with system
  voices (note: system recognizer may use Apple services — disclosed).
- C8 — persistence: SwiftData via an actor (`SwiftDataService`,
  `cloudKitDatabase: .none`), autosave off, serial executor; versioned
  `MoltenMigrationPlan` (1.1 → 2.0 schema upgrade verified, C4/A10).
- C9 — performance: throttling + buffering chosen so long responses
  can't freeze the UI; markdown/code rendering components reused from 1.x.

---

## 5. Conversations & context utilities (F-CONV, F-CTX) — **free for all**

- V1 — **full-text search** across all conversations (SQLite FTS5
  sidecar kept in sync by every create/update/delete/day-delete path),
  with snippets and jump-to-result (C1 module).
- V2 — **export**: Markdown or JSON per conversation (analytics
  optional), or everything as a zip; **import** from JSON with FTS and
  store refresh (C2/C3).
- V3 — **auto-titles** after the first exchange — Apple on-device model
  first, active model as fallback; only while the conversation still
  has its default name; user-editable; toggle in Settings.
- V4 — **context meter**: composer ring of estimated tokens vs the
  model's window (Ollama: per-model `num_ctx` from `/api/show`;
  OpenAI-compatible: user setting, default 8192; Apple: 4096); 80 %
  orange, 95 % red warnings.
- V5 — automatic history budgeting: newest-first packing with a reply
  reserve `min(1024, window/4)`; the newest message is never dropped;
  system/grounding messages preserved (X2).
- V6 — day-grouped sidebar deletion (delete-a-day safety) and
  delete-everything confirmation.

---

## 6. Platform scope & requirements (F-PLAT)

- PL1 — macOS 26.0+, iOS/iPadOS 26.0+, one target, universal Mac binary
  (arm64 + x86_64); **visionOS support removed** in 2.0 (M0 cleanup).
- PL2 — macOS extras: floating quick-access panel (⌘⌥K), menu-bar
  control, completions editor, keyboard shortcuts.
- PL3 — App Sandbox on app *and* share extension; hardened runtime;
  network-client + user-selected-files (read-only) entitlements;
  background processing task registration; `NSUbiquitousContainers`
  declared with public document scope.
- PL4 — export compliance: `ITSAppUsesNonExemptEncryption=false` (only
  Apple-OS crypto + SHA-256 hashing; LZFSE is compression).
- PL5 — build/versioning: marketing 2.0, build 10; all targets share the
  build number (App Store validation requirement).

## 7. Privacy & security (F-PRIV)

- PR1 — no Molten servers, no accounts, no telemetry, no analytics
  upload. Period.
- PR2 — all inference on-device; Knowledge syncs through the user's own
  iCloud container; Advanced Data Protection gives E2EE.
- PR3 — the only external network traffic: user-configured local
  inference servers and (with consent) the one-time e5-small download
  from huggingface.co; plus App Store/Keychain (Apple) for entitlements.
- PR4 — full source Apache-2.0; builds reproducible via committed
  `Package.resolved`.

## 8. Quality bar achieved (F-QA)

- 133 automated tests (53 XCTest + 80 Swift Testing) across M0–M7 +
  review-round suites; both platforms build green.
- Performance acceptance on hardware: 100-page PDF extract+chunk gate
  < 60 s — measured **0.21 s** on Mac (0.28 s simulator, 215 chunks);
  20,000-chunk hybrid search gate < 200 ms — measured **50.8 ms** Mac
  / 53.3 ms simulator (`docs/SPIKE.md` A1/A4).
- Cross-device embedding agreement ≥ 0.999 cosine (measured 0.9999985).
- Two dedicated review rounds before release: **22 bugs found and
  fixed**; a third iOS-testing round fixed the knowledge UI, Use-in-Chat
  flow, and AFM grounding.
- Physical upgrade path 1.1 → 2.0 verified via TestFlight before release.

## 9. Marketing summary — what 2.0 actually does

**Headline:** *Your documents joined the conversation.* Molten 2.0 is a
free download for Mac, iPhone and iPad: local AI chat on any of three
backends, now with **cited answers from your own documents** — processed
once on your Mac, shared through your own iCloud, never through ours.

Claim-ready, all true as shipped:

- **Truly private RAG** — embeddings and search run on-device (MLX,
  Apple Silicon); the shared index is content-addressed, so renaming or
  duplicating a file never triggers rework.
- **Answers you can verify** — numbered citations; tap one to open the
  exact source file (Quick Look on iOS).
- **Hybrid search that never breaks** — semantic + keyword merged with
  reciprocal rank fusion; keyword mode works offline and before the
  480 MB model download.
- **One device does the heavy lifting** — your Mac; iPhone and iPad
  reuse finished results, background processing survives app switches.
- **Your data, your cloud** — no accounts, no servers, no telemetry;
  end-to-end encrypted with Advanced Data Protection.
- **Built for Apple Silicon** — cross-device vector agreement
  > 0.99999 measured; 20k-chunk search in ~50 ms.
- **Free chat stays free** — every backend, every conversation feature
  (search, export/import, auto-titles, context meter) is free forever;
  Plus (US$2.99/mo, US$19.99/yr w/ 1-week trial, US$49.99 lifetime)
  unlocks unlimited Knowledge.
- **Early Supporters for life** — pre-2.0 buyers automatically get Plus
  forever, on every device, no code needed.

**Explicit non-goals / deferred (honesty for both marketing and
planning):** index encryption (reserved 2.1), chat-history iCloud sync
(2.1), Pro tier & tool-calling/MCP (2.2+), voice mode on Mac (2.4+);
macOS share extension is currently a placeholder; the context meter
estimates (~4 chars/token) rather than running a full tokenizer over
chat text; Apple's on-device model grounds with max 3 chunks by design
(4096-token window) while bigger-window models get up to 8.

## 10. Where 2.0 code hooks the next versions

- `Capabilities.pro*` and `Tier.pro` already exist → Pro plugs in.
- `.mkt/.mkv` `encryption` field reserved (must be null today) → P5
  2.1 index encryption without format change.
- `MoltenMigrationPlan` + `ProfileMigration` patterns are the template
  for future schema/profile moves.
- `docs/BUILD_AUTOMATION.md` makes 2.x releases a one-command pipeline.
- Roadmap (README): 2.1 iCloud chat sync/personas/auto-compact/index
  encryption · 2.2 tools/MCP + Pro · 2.3 compare/branching/artifacts ·
  2.4+ voice mode, memory, App Intents.

---

*Reconstructed 2026-11-21 from the shipped `v2.0` tag. When a future
release changes any behavior above, update this file in the same PR.*