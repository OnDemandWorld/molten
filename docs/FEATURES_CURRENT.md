# Molten — Current Feature Inventory (v2.0.1, build 12)

**Purpose:** a factual, code-verified feature list for monetization design.
Every entry says what the feature does, who gets it today, and *where the
gate or limit lives in code* so a new free/paid line can be drawn by
changing one constant or one `Feature` case. Companion docs:
`docs/PRD_v2.0.md` (shipped 2.0 spec, feature IDs reused here) and
`CODE_REVIEW_2026_11_24.md` (defects that affect enforcement reliability).

**Snapshot:** native SwiftUI chat client for **local LLMs** on macOS 26 /
iOS 26 / iPadOS 26. Backends: Ollama, any OpenAI-compatible server
(Swama/oMLX/…), Apple Foundation Models. Private document chat (RAG) with
citations, synced through the user's own iCloud. No Molten servers, no
accounts, no telemetry. Apache-2.0 source.

---

## 1. Monetization state today

### Tiers & products (all client-side, StoreKit 2)

| Item | Value | Code |
|---|---|---|
| Tiers | `free`, `plus`, `pro` (**pro reserved, nothing gates on it yet**) | `Entitlements.swift` `Tier` |
| Plus Monthly | `molten.plus.monthly` — US$2.99/mo | `Molten.storekit` |
| Plus Yearly | `molten.plus.yearly` — US$19.99/yr, **1-week free trial** | `Molten.storekit` |
| Plus Lifetime | `molten.plus.lifetime` — US$49.99 non-consumable | `Molten.storekit` |
| Early Supporter | first purchase before 2.0 (iOS build ≤ 6 / macOS original version < 2.0) → **Plus forever**, auto-detected via `AppTransaction`, mirrored to synchronizable Keychain, works offline | `EarlySupporterDetector.swift`, `EntitlementKeychain.swift` |
| Tier math | `max(earlySupporter→plus, activeSubscription, lifetime→plus)`; subscription grants only with a **future** expiration (lapse = downgrade, nothing deleted) | `EntitlementManager.computeTier` |
| Paywall | shown **only on intent** (hit a limit / tap Plan), never at launch; native `SubscriptionStoreView` + lifetime card | `PaywallView.swift` |

### The gate API (single choke point)

```swift
enum Feature { case unlimitedKnowledge, iCloudKnowledge, macAssist, ocr }
// every case currently requires .plus
EntitlementManager.shared.allows(_ feature) -> Bool   // tier >= requiredTier
```

- **`macAssist` is declared but has ZERO call sites** — an unused gate,
  available for a future paid line (e.g. macOS panel/completions).
  (`docs/PRD_v2.0.md` T2 lists `priorityProcessing` instead — that name
  does not exist in code; this document reflects the code.)
- All enforcement is **client-side**. There is no server to validate
  usage; any meter you add is only as strong as the local check. The
  source is Apache-2.0 (forks can strip gates — price for convenience,
  not for secrets).
- Pro tier plumbing exists (`molten.pro.*` product IDs recognized in
  `EntitlementManager.refresh`) but no product is configured and no
  feature requires it.

### What Free vs Plus actually get today

| Capability | Free | Plus |
|---|---|---|
| Chat, all 3 backends, unlimited messages/models | ✅ | ✅ |
| macOS floating panel, hotkeys, completions editor | ✅ | ✅ |
| Voice input + read-aloud | ✅ | ✅ |
| Conversation search/export/import, auto-titles, context meter | ✅ | ✅ |
| Knowledge bases | **1 base** | unlimited |
| Documents per base | **10** (but see §5 gap G1) | unlimited |
| "Use a document once in this chat" (no indexing) | ✅ | ✅ |
| Keyword (FTS) search over indexed docs | ✅ | ✅ |
| **Semantic/hybrid search (embeddings)** | ✅ **not tier-gated** (only needs the free model download + a capable device) | ✅ |
| OCR for scanned PDFs/images | ❌ | ✅ |
| iCloud Knowledge sync (Mac↔iPhone↔iPad) | ❌ local-only | ✅ |
| Cross-device process-once/reuse-everywhere | ❌ (follows sync) | ✅ |

---

## 2. Feature inventory

Availability: **All** = free for everyone · **Plus** = gated today ·
**All⚠** = free but with a caveat noted. Hook = file you'd touch to gate/meter it.

### A. Chat core (F-CHAT)

| ID | Feature | Avail | Hook / notes |
|---|---|---|---|
| A1 | Ollama backend (native API, model list, streaming) | All | `OllamaService.swift`; URL/token in Settings |
| A2 | OpenAI-compatible backend (Swama/oMLX/any `/v1/chat/completions`, SSE) | All | `SwamaService.swift`; per-server context-window setting |
| A3 | Apple Foundation Models backend (on-device, no server) | All | `AppleFoundationService.swift`; macOS/iOS 26 only |
| A4 | Provider reachability polling + smart backoff; empty URL disables a provider | All | `AppStore.swift`, `ModelProviderProtocol.swift` |
| A5 | Streaming chat with Stop, throttled UI, mid-stream conversation switch | All | `ConversationStore.swift` |
| A6 | System prompt, multi-turn history, edit-and-resend (trim) | All | `ConversationStore.sendPrompt` |
| A7 | Image input on vision-capable models | All⚠ | attach UI per model `supportsImages`; **Ollama image parts are currently dropped** (review M-findings) |
| A8 | Per-message analytics footer (tokens, timings, rates; server usage wins, estimates labeled) | All | `ConversationStore.computeAnalytics`, `AnalyticsFooterView.swift` |
| A9 | Markdown + syntax-highlighted code rendering, copy | All | `ChatMessageView.swift`, `SplashSyntaxHighlighter+Extension.swift` |
| A10 | Read-aloud (system voices, voice picker) | All | `SpeechService.swift`, `ReadingAloudView.swift` |
| A11 | Voice input (speech-to-text) | All⚠ | `SpeechRecogniser.swift`; **not forced on-device today** — audio may go to Apple servers (review finding); relevant if you market privacy |
| A12 | Prompt suggestions / sample prompts | All | `PromptSuggestionsStore.swift`, `SamplePrompt.swift` |

### B. macOS power-user surface

| ID | Feature | Avail | Hook / notes |
|---|---|---|---|
| B1 | Floating quick-access PromptPanel (⌘⌥K), works over any app | All | `PanelManager.swift`, `PromptPanel.swift` — **natural `macAssist` candidate** |
| B2 | Grab selected text from any app (accessibility + copy fallback) | All | `Accessibility.swift` |
| B3 | Completions editor: reusable prompt templates with `{selection}` | All | `CompletionsStore.swift`, `CompletionsEditor/` — no count limit today |
| B4 | In-app / in-window completion execution, typed-out results | All | `CompletionPanelView.swift`, `PanelCompletionsVM.swift` |
| B5 | Global hotkeys, menu-bar integration | All | `HotKeys.swift`, `HotkeyService.swift`, `Menus.swift` |

### C. Knowledge / RAG (F-KNOW)

| ID | Feature | Avail | Hook / notes |
|---|---|---|---|
| C1 | Knowledge bases (folders), sidebar counts & status vocabulary | **1 free / ∞ Plus** | `KnowledgeLimits.freeBaseCount = 1` (`KnowledgeIndexer.swift:26`); gate at `KnowledgeViews.swift:113` |
| C2 | Add documents: PDF, TXT/MD, RTF, HTML, DOCX | **10 free / ∞ Plus** | `KnowledgeLimits.freeDocumentCount = 10` (`KnowledgeIndexer.swift:27`); gates at `KnowledgeViews.swift:304,410` + `KnowledgeIndexer.scan` |
| C3 | OCR for scanned PDFs & images (PNG/JPEG/HEIC, Vision) | **Plus** | `Feature.ocr`; prefilter `KnowledgeIndexer.swift:71,174`; threshold `Extractors.ocrThreshold = 50` chars |
| C4 | iCloud sync of sources + finished outputs (user's own container) | **Plus** | `Feature.iCloudKnowledge`; `KnowledgeContainer.swift:46,61` |
| C5 | Process-once on Mac, reuse on every device (content-addressed `.mkt`/`.mkv`) | **Plus** (follows C4) | `Watchers.swift`, `CoordinatedIO.swift` |
| C6 | Device roles: iPhone/iPad defer to a fresh Mac; policy `bothWhileCharging`/`alwaysBoth`; "Process Now" override | All (within sync) | `DeviceRoles` (`HeartbeatService.swift:97+`), heartbeats 15 min, Mac freshness 24 h |
| C7 | Semantic search: e5-small-v2 embeddings (MLX, 384-dim, fp16 vectors) | **All** (no tier gate) | `EmbeddingService.swift`, `Retriever.swift` — model download ~480 MB, consent on cellular (`ModelDownloadConsent.swift`) |
| C8 | Hybrid retrieval: FTS5 BM25 + cosine, reciprocal-rank fusion; keyword-only fallback labeled | All | `KnowledgeStore.search`, `Retriever.retrieve(limit: 8)` |
| C9 | Grounded answers with numbered citations; tap chip → open source file | All (needs indexed base) | `PromptAssembler.swift`, citation chips in `ChatMessageView` |
| C10 | `@Base name …` attach / "Use in Chat" button, per-conversation base chip | All | `ConversationStore.sendPrompt`, `KnowledgeViews` |
| C11 | "Use a document once in this chat" — free, no indexing | All | `UseOnce.extractText(budgetTokens: 6000)` (`Extractors.swift:282`) |
| C12 | Passage search without an LLM | All | `Retriever.passages(limit: 20)` |
| C13 | Share extension "Add to Molten Knowledge" (iOS) | All (into free limits) | `ShareViewController.swift`; **50 MB share cap** (new fix) |
| C14 | Background processing continuation (iOS BGContinuedProcessingTask) | All | `KnowledgeBackgroundTask.swift` |
| C15 | Index cleanup: unreferenced outputs deleted after 7-day grace | All | `KnowledgeCleanup.graceDays = 7` |
| C16 | First-base onboarding + privacy disclosure | All | `KnowledgeViews` onboarding sheet |

### D. Conversations & data (F-CONV/F-CTX) — all free today

| ID | Feature | Avail | Hook / notes |
|---|---|---|---|
| D1 | Full-text conversation search (FTS5 sidecar, snippets, jump-to) | All | `ConversationSearch.swift`; sidebar query LIMIT 50 |
| D2 | Export: Markdown/JSON per conversation, zip-all | All⚠ | `Exporter.swift`; **images dropped from export today** (review finding) |
| D3 | Import from JSON | All | `Importer.swift` |
| D4 | Auto-titles (AFM first, active model fallback; toggle in Settings) | All | `AutoTitler.swift` |
| D5 | Context meter ring (80%/95% warnings) + automatic history budgeting | All | `ContextWindow.swift`, `ContextBudget.swift` |
| D6 | Day-grouped sidebar, delete-a-day, delete-all | All | `SidebarView.swift`, `SwiftDataService` |
| D7 | Knowledge export/import (zip) | All | `KnowledgeViews.swift:539+` |

### E. Settings & personalization — all free today

Provider URLs + bearer/API keys · default model · system prompt ·
appearance (light/dark/system) · ping interval · vibrations · voice
identifier · user initials · Swama context window · Knowledge processing
policy · subscription management (plan row, restore).

---

## 3. Every numeric limit in the code (metering candidates)

| Limit | Value | Location |
|---|---|---|
| Free bases | 1 | `KnowledgeIndexer.swift:26` `freeBaseCount` |
| Free documents/base | 10 | `KnowledgeIndexer.swift:27` `freeDocumentCount` |
| OCR text threshold | 50 chars/page | `Extractors.swift:81` `ocrThreshold` |
| Use-once doc budget | 6000 tokens | `Extractors.swift:282` |
| Grounding passages | 8 (AFM: ≤3 chunks / ~1536 tokens) | `Retriever.retrieve(limit:)`, `ConversationStore.sendPrompt` |
| Passage lookup | 20 | `Retriever.passages(limit:)` |
| Chunk target / hard cap | ~350 / 480 tokens | `Chunker.swift` (cap violated on some inputs — review finding) |
| Embedding model window | 512 tokens (silent truncation) | `EmbeddingService.swift` |
| Context window default | 8192 (Ollama: per-model `num_ctx`; AFM: 4096) | `ContextWindow.swift` |
| Reply reserve | min(1024, window/4) | `ContextBudget.defaultReserve` |
| Sidebar search results | 50 | `ConversationSearch`/sidebar query |
| Claim lease | 10 min (renewal **not implemented** — review finding) | `ClaimStore.swift` |
| Heartbeat cadence / Mac freshness | 15 min / 24 h | `HeartbeatService.swift:25`, `DeviceRoles.macFreshness` |
| Cleanup grace | 7 days | `KnowledgeCleanup.graceDays` |
| Embedding model download | ~480 MB, cellular consent | `HFSnapshotDownloader.swift`, `ModelDownloadConsent.swift` |
| Share-extension file cap | 50 MB (added 2026-11-24) | `ShareViewController.maxShareBytes` |
| DOCX inflate cap | 64 MiB (added 2026-11-24) | `Extractors.inflateRawDeflate` |
| Reachability ping / backoff | macOS 15 s, iOS 30 s; 30→300 s / 10→60 s; 2 s timeout | `AppStore.swift` |

**Not limited today (greenfield meters):** messages/day, conversations
count, completions count, panel invocations, number of providers/URLs,
devices per account (no accounts exist), export frequency, voice
minutes, semantic-search queries, bases size on disk.

---

## 4. Candidate monetization lines (facts, not recommendations)

Each lever below lists what exists to hang a gate on. All are
client-enforced; combine with §5 gaps before committing to a line.

1. **Volume lines (existing, tunable):** bases (1) and documents/base
   (10) are one-constant changes (`KnowledgeLimits`). Could become
   tiered (e.g. Free 1/10, Plus 5/100, Pro ∞) by making the limits
   tier-dependent instead of boolean.
2. **OCR (existing Plus gate):** clean prefilter already in the indexer;
   could be metered per-page instead of binary.
3. **Sync/devices (existing Plus gate):** `iCloudKnowledge` gates the
   container root. Device count is observable via heartbeats
   (`HeartbeatService.devices()`) — a "N devices" line is feasible
   without accounts, but enforcement is advisory (each device decides).
4. **`macAssist` (declared, unenforced):** ready-made hook for gating the
   macOS panel/completions surface (B1–B5) — currently 100% free.
5. **Semantic search (currently ungated):** C7/C8 are free for anyone
   who downloads the model. Gating hybrid mode (keep keyword free) is a
   one-call change in `Retriever.retrieve` — but it's a strong current
   free-tier selling point.
6. **Use-once budget (free path):** 6000-token budget in `UseOnce` is a
   natural meter (tokens/day) if you want the free path to stay useful
   but bounded.
7. **Grounding depth:** passages 8 / AFM 3 are constants in the send
   path — a "deeper grounding" paid line is mechanically trivial.
8. **Pro tier (reserved):** `Tier.pro`, `molten.pro.*` recognition, and
   `Feature.requiredTier` already support a third tier with zero
   plumbing work; nothing currently requires it.
9. **Data portability (D2/D3/D7):** export/import are free; gating
   zip-all or import behind Plus is possible but conflicts with the
   "your data is yours" positioning and the Apache-2.0 fork reality.
10. **Voice (A10/A11):** free today; minutes-based metering would need
    new counters (none exist). Note A11's on-device caveat first.

**Positioning constraints baked into the product** (from PRD §1, still
true in code): core chat free forever; no accounts/servers; privacy by
architecture; Early Supporters permanently Plus (any new line must
decide whether ES grants it — today ES = Plus, so Plus-gated features
are included, Pro-gated ones would not be).

---

## 5. Enforcement gaps that affect any limit line

From `CODE_REVIEW_2026_11_24.md` (medium findings, still open):

- **G1 — Free document gate is bypassable on iOS:** the limit counts
  *indexed* documents, which stay 0 while iOS defers processing to Mac
  (`KnowledgeViews.swift:408`). Unlimited files can be added on iOS
  without the paywall ever firing. Fix before relying on the 10-doc line.
- **G2 — Mid-session purchase doesn't activate sync:** Knowledge root
  is resolved only at launch; a Plus bought mid-session leaves iCloud
  inert until relaunch (`EntitlementManager.swift:102`,
  `KnowledgeContainer.swift:33`). Paywall promises immediate value.
- **G3 — Base-name traversal:** `createBase` accepts `..`/`/` names
  (`KnowledgeViews.swift:122`, `ShareViewController.swift:101`) — a
  `..` base exposes the Index folder as removable "files".
- **G4 — Lapse behavior:** downgrade keeps everything searchable
  (by design, T6) but stale iCloud root/watchers persist until relaunch
  (same root cause as G2).
- **G5 — Restore gives no feedback** (`EntitlementManager.restore`
  swallows errors) — offline restore looks like "nothing to restore".

High-severity defects (crash/data-loss) were fixed on branch
`fix/review-2026-11-24-highs`; the medium list above is the part that
touches monetization reliability.

---

## 6. Delta vs `docs/PRD_v2.0.md`

- `Capability`/`priorityProcessing` (PRD T2) → code actually has
  `Feature` with `macAssist` (unenforced). No priority-processing gate
  exists.
- Version is now **2.0.1 (build 12)**: knowledge count refresh,
  off-main file I/O, AFM availability fixes (PRs #13/#14) plus the
  2026-11-24 review fixes (share cap, inflate cap, cancellation safety).
- PRD §10 roadmap unchanged: 2.1 chat sync/personas/index encryption ·
  2.2 tools/MCP + Pro · 2.3 compare/branching · 2.4+ voice mode/memory.

*Reverse-engineered 2026-11-24 from `main` + `fix/review-2026-11-24-highs`.
Update this file in the same PR whenever a gate, limit, or product changes.*