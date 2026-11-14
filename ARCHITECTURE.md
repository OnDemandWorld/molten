# Molten Architecture Documentation

This document provides a detailed technical overview of Molten's architecture, design patterns, and implementation details.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Data Flow](#data-flow)
4. [Model Provider System](#model-provider-system)
5. [State Management](#state-management)
6. [Data Persistence](#data-persistence)
7. [UI Architecture](#ui-architecture)
8. [Concurrency Model](#concurrency-model)
9. [Performance Optimizations](#performance-optimizations)

## Architecture Overview

Molten follows a **layered architecture** with clear separation of concerns:

```
┌─────────────────────────────────────┐
│         UI Layer (SwiftUI)          │
│  macOS Views | iOS Views | Shared   │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│      State Management (@Observable)  │
│  Stores: Conversation, Model, App   │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│        Services Layer                │
│  Providers | Data | Speech | etc.    │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│      Data Layer (SwiftData)         │
│  Models: Conversation, Message, etc.│
└─────────────────────────────────────┘
```

## Core Components

### 1. Model Provider System

The model provider system is the heart of Molten's multi-backend support.

#### ModelProviderProtocol

```swift
protocol ModelProviderProtocol: Sendable {
    func reachable() async -> Bool
    func getModels() async throws -> [LanguageModel]
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error>
}
```

**Purpose**: Unified interface for all model providers (Ollama, Swama, Apple Foundation)

**Key Design Decisions**:
- Uses `AsyncThrowingStream` for streaming responses
- All providers return standardized `ChatCompletionResponse`
- Provider-specific implementations handle API differences internally

#### Provider Implementations

**OllamaService**
- Uses OllamaKit library for API communication
- Converts Combine `AnyPublisher` to `AsyncThrowingStream`
- Handles Ollama-specific message format conversion

**SwamaService**
- Uses OpenAI-compatible API format
- Implements Server-Sent Events (SSE) parsing
- Handles streaming and non-streaming responses

**AppleFoundationService**
- Uses `LanguageModelSession` from FoundationModels framework
- Simulates streaming by chunking responses
- Only available on macOS 26.0+

### 2. State Management

Molten uses Swift's `@Observable` macro for reactive state management.

#### ConversationStore

**Responsibilities**:
- Managing conversation state
- Handling message streaming
- Throttling UI updates
- Analytics tracking

**Key Features**:
- `@MainActor` isolation for UI updates
- Throttled updates to prevent UI freezing
- Analytics tracking (timing, tokens, rates)

**State Flow**:
```
User Input → sendPrompt() → Provider.chatStream() 
→ handleReceive() → UI Update (throttled) 
→ handleComplete() → Analytics Calculation
```

#### LanguageModelStore

**Responsibilities**:
- Fetching models from all providers
- Caching models locally
- Model selection and filtering

**Key Features**:
- Automatic model discovery on app launch
- Provider-specific model prefixing (O:, S:, A:)
- Filtering unavailable models

### 3. Data Persistence

#### SwiftDataService

**Architecture**: Actor-based for thread safety

**Responsibilities**:
- Conversation CRUD operations
- Message storage
- Model caching
- Completion instruction storage

**Key Design**:
- Uses `@Model` macro for SwiftData models
- Actor isolation prevents data races
- Proper QoS handling to avoid priority inversions

#### Data Models

**ConversationSD**
- Represents a conversation thread
- Contains messages, model reference, timestamps
- Supports system prompts

**MessageSD**
- Individual messages within conversations
- Stores content, role, timestamps
- Includes analytics fields (tokens, timing)
- Supports image attachments

**LanguageModelSD**
- Cached model information
- Provider association
- Display name with prefix

## Data Flow

### Chat Request Flow

```
1. User types message → ChatView
2. ChatView calls ConversationStore.sendPrompt()
3. ConversationStore:
   a. Creates user message
   b. Creates assistant message (empty)
   c. Gets provider from model
   d. Calls provider.chatStream()
4. Provider streams responses:
   a. Each chunk → handleReceive()
   b. Content extracted and buffered
   c. Throttled UI updates
5. Stream completes → handleComplete()
   a. Flush buffer
   b. Calculate analytics
   c. Save to SwiftData
   d. Update UI state
```

### Model Discovery Flow

```
1. App Launch → LanguageModelStore.loadModels()
2. For each provider:
   a. Check reachable()
   b. If reachable, call getModels()
   c. Convert to LanguageModelSD
   d. Save to SwiftData
3. Filter stored models to only available ones
4. Update UI with model list
```

## Model Provider System

### Provider Selection

The system uses a factory pattern to get the appropriate provider:

```swift
private func getProvider(for model: LanguageModelSD) -> ModelProviderProtocol? {
    guard let provider = model.modelProvider else { return nil }
    switch provider {
    case .swama: return SwamaService.shared
    case .ollama: return OllamaService.shared
    case .appleFoundation: return AppleFoundationService.shared
    }
}
```

### Provider Configuration

**Default Behavior**:
- Ollama defaults to `http://localhost:11434` if no URL configured
- Swama defaults to `http://localhost:28100` if no URL configured
- Services track whether using default vs user-configured URLs
- This enables smart backoff strategies in reachability polling

**Configuration Priority**:
1. Explicit URL parameter (when called from Settings)
2. Stored UserDefaults value
3. Default localhost (if neither above is set)

**Reachability Behavior**:
- Services return `false` immediately if URL is explicitly empty (no polling)
- Services make HTTP requests with 2s timeout if configured
- AppStore coordinates polling with caching and backoff

### Message Format Conversion

Each provider converts messages to/from the unified `ChatMessage` format:

**Ollama**: Uses `OKChatRequestData.Message` with role enum
**Swama**: Uses OpenAI-compatible format directly
**Apple Foundation**: Converts to simple prompt string

### Streaming Implementation

All providers use `AsyncThrowingStream` for consistent streaming:

```swift
func chatStream(...) -> AsyncThrowingStream<ChatCompletionResponse, Error> {
    AsyncThrowingStream { continuation in
        Task {
            // Provider-specific streaming logic
            // Yields ChatCompletionResponse chunks
            continuation.finish()
        }
    }
}
```

## State Management

### Observable Pattern

All stores use `@Observable` macro:

```swift
@Observable
final class ConversationStore {
    @MainActor var conversationState: ConversationState
    @MainActor var messages: [MessageSD]
    // ...
}
```

**Benefits**:
- Automatic UI updates on state changes
- Type-safe property access
- No manual `@Published` or `objectWillChange` needed

### Main Actor Isolation

UI-related state is isolated to `@MainActor`:

- Prevents data races
- Ensures UI updates on main thread
- Clear concurrency boundaries

## Data Persistence

### SwiftData Integration

**Model Definition**:
```swift
@Model
final class ConversationSD {
    var name: String
    var messages: [MessageSD]
    var model: LanguageModelSD?
    // ...
}
```

**Actor-Based Service**:
```swift
actor SwiftDataService {
    func createMessage(_ message: MessageSD) async throws {
        // Thread-safe database operations
    }
}
```

### Data Migration

`MoltenMigrationPlan` (versioned `SchemaMigrationPlan`, currently `MoltenSchemaV2` = 2.0.0) is wired into the data actor's `ModelContainer`. v1.1 → 2.0 adds only optional properties (`ConversationSD.attachedKnowledgeBase`, `MessageSD.knowledgeCitationsData`), which SwiftData migrates lightweight. Future releases add stages to the plan.

**Critical:** the container uses `cloudKitDatabase: .none`. With iCloud entitlements present, SwiftData's `.automatic` default enables CloudKit integration, which rejects non-optional attributes without defaults (launch crash on device). Chat-history sync is a 2.1 feature and will revisit this deliberately.

## UI Architecture

### Platform-Specific Views

**macOS**: `ChatView_macOS.swift`, `InputFields_macOS.swift`
**iOS**: `ChatView_iOS.swift`

**Shared**: `ChatMessageView`, `ModelSelectorView`, `SettingsView`

### Platform Notes

- **Asset Catalogs**: Shared imagesets must include `universal` idioms for iOS/iPadOS. Mac-only assets will not render on iPhone/iPad.
- **Streaming Indicator**: The assistant avatar switches from spinner to `logo-nobg` when `MessageSD.done` is set in `ConversationStore.handleComplete()`.

### Component Hierarchy

```
ApplicationEntry
├── Chat
│   ├── SidebarView (macOS)
│   ├── ChatView
│   │   ├── Header (Model Selector)
│   │   ├── MessageListView
│   │   │   └── ChatMessageView
│   │   │       └── AnalyticsFooterView
│   │   └── InputFields
│   └── ConversationStatusView
└── Settings
    └── SettingsView
```

### Reactive Updates

SwiftUI automatically updates when:
- `@Observable` properties change
- SwiftData models change
- `@State` variables change

## Concurrency Model

### Async/Await

All asynchronous operations use async/await:

```swift
func loadModels() async throws {
    let swamaModels = try await SwamaService.shared.getModels()
    // ...
}
```

### Task Management

Proper task cancellation:

```swift
generationTask = Task {
    // ...
    if Task.isCancelled { break }
}
```

### Actor Isolation

- `SwiftDataService`: Actor for thread-safe database access
- `@MainActor`: UI-related state and operations
- `nonisolated(unsafe)`: Static singletons (controlled access)

## Performance Optimizations

### 1. UI Update Throttling

Streaming responses are throttled to prevent UI freezing:

```swift
private let throttler = Throttler(delay: 0.15)
// Leading+trailing throttle: flushes every 150ms even under continuous
// streaming (a debounce would wait for a pause).
```

### 2. Smart Reachability Polling

The app uses intelligent polling strategies to minimize network requests and reduce error noise:

**Caching Strategy**:
- Reachability results cached for 10 seconds (TTL)
- Prevents redundant HTTP requests within cache window
- Cache invalidated on manual checks or state changes

**Exponential Backoff**:
- **Default Localhost** (when no URL configured):
  - Base interval: 30 seconds
  - Progression: 30s → 60s → 120s → 240s → 300s (max)
  - Rationale: Localhost services often aren't running, so aggressive backoff reduces error spam
  
- **User-Configured URLs**:
  - Base interval: 10 seconds  
  - Progression: 10s → 20s → 40s → 60s (max)
  - Rationale: User explicitly configured URL, so check more frequently

**Platform-Specific Defaults**:
- **macOS**: 15 seconds (desktop, less battery concern)
- **iOS/iPadOS**: 30 seconds (mobile, optimized for battery life)
- Users can customize in Settings
- Backoff strategies apply on top of these defaults

**Timeout Protection**:
- All reachability checks have 2-second timeouts
- Prevents long waits when services are unreachable
- Prevents connection errors from blocking the UI

**Configuration Detection**:
- Services track whether using default localhost vs user-configured URLs
- Different backoff strategies applied based on configuration
- No polling if URL fields are explicitly empty

### 3. Lazy Loading

- Models loaded on-demand
- Conversations loaded as needed
- Images loaded lazily

### 4. Efficient Data Structures

- Arrays for ordered collections
- SwiftData for persistence
- In-memory caching for frequently accessed data

### 5. Memory Management

- Weak references in closures
- Proper task cancellation
- Image compression for storage

## Error Handling

### Error Types

- **Network Errors**: Provider unreachable, connection failures
- **API Errors**: Invalid requests, model not found
- **Data Errors**: Decoding failures, missing data

### Error Recovery

- Automatic retry for transient failures
- User-friendly error messages
- Graceful degradation (fallback to available providers)

## Testing Strategy

`MoltenTests` (hosted in Molten.app): **53 XCTest + 80 Swift Testing** tests.
New tests use Swift Testing; both frameworks coexist.

- **XCTest (v1.1):** analytics, Apple prompt assembly, conversation-store
  errors, day-deletion safety, prompt suggestions, Swama request wiring,
  throttler cadence.
- **Swift Testing (2.0):** M2 entitlement matrix + StoreKit flows
  (buy/lapse/lifetime/ES+subscription, gated by
  `build/session/STOREKIT_FLOWS_ENABLED`); M3 codecs/chunker/retrieval/
  extraction/e2e pipeline; M4 manifest/coordinated-IO/mapping; M5 claims/
  roles/heartbeats/resume durability; M6 export/import/search/migration;
  M7 profile migration + performance acceptance (A1/A4, gated by
  `build/session/MOLTEN_PERF`); M1 embedding spike (gated by
  `build/session/SPIKE_ENABLED`, cross-device compare by `SPIKE_COMPARE`).

Run: `xcodebuild test -scheme Molten -destination 'platform=macOS'
-enableCodeCoverage NO` (default coverage fails linking the yyjson C
dependency — `___llvm_profile_runtime` — a toolchain artifact).

Acceptance measurements (docs/SPIKE.md): A1 100-page PDF 0.21s Mac / 0.28s
sim; A4 20k-chunk hybrid search 50.8ms Mac / 53.3ms sim; K-E5 cross-device
min cosine 0.9999985 (iPhone vs Mac, hardware-verified).

## Security Considerations

### Data Privacy

- All data stored locally
- No network calls except to user-configured providers
- No telemetry or analytics

### Code Signing

- Proper entitlements for macOS features
- Sandboxing where appropriate
- Secure storage for sensitive data

## Molten 2.0 Subsystems

2.0 adds a freemium tier system and the Knowledge workspace. Module layout
(PRD §7.1):

```
Molten/
├── Entitlements/      Tier/Feature, EntitlementManager, EarlySupporterDetector,
│                      EntitlementKeychain, PaywallView, SubscriptionSettingsSection,
│                      Molten.storekit (local StoreKit configuration)
├── Knowledge/
│   ├── Container/     KnowledgeContainer (iCloud vs local root, migration),
│   │                  CoordinatedIO (NSFileCoordinator, download-on-read)
│   ├── Watch/         DocumentWatcher, IndexWatcher (NSMetadataQuery),
│   │                  FileMapping (path→hash), KnowledgeSync, KnowledgeCleanup
│   ├── Process/       KnowledgeIndexer, ClaimStore, HeartbeatService,
│   │                  DeviceRoles, Chunker, Extractors, ShareImport,
│   │                  DeviceIdentity, KnowledgeBackgroundTask
│   ├── Embed/         EmbeddingService (MLXEmbedders), EmbeddingProfile,
│   │                  HFSnapshotDownloader, ModelDownloadConsent, ProfileMigration
│   ├── Store/         KnowledgeStore (SQLite FTS5 + vectors), MKT/MKV codecs,
│   │                  Manifest
│   ├── Retrieve/      Retriever (hybrid RRF), PromptAssembler (citations)
│   └── UI/            KnowledgeSidebar, BaseDetailView, KnowledgeOnboarding,
│                      CitationChips (Quick Look on iOS), settings sections
├── Context/           ContextBudget, ContextWindow, ContextRing, TokenEstimator
├── Conversations/     ConversationSearch (FTS5 sidecar), Exporter (+ZipWriter),
│                      Importer, AutoTitler
└── ShareExtension/    MoltenShare target (iOS share sheet; macOS placeholder)
```

### Entitlements (Free / Plus / Pro-later)

- `EntitlementManager` (actor) computes
  `currentTier = max(earlySupporter ? .plus : .free, active subscription, lifetime)`
  and publishes to `EntitlementUIModel` (`@Observable`, main actor). It listens
  to `Transaction.updates` from launch and finishes transactions.
- **Early Supporter** (`EarlySupporterDetector`): `AppTransaction.originalAppVersion`
  vs per-platform cutoffs — macOS marketing version ("2.0"), iOS build number
  (`iosCutoffBuild = 7`; highest shipped 1.x build was 6). Sandbox/Xcode
  environments NEVER grant; a DEBUG-only simulate toggle is compiled out of
  Release. The grant is persisted as a **synchronizable iCloud Keychain** item
  (`molten.entitlement`/`earlySupporter`) so any device grants Plus offline.
- **Gating**: every gated feature is a `Feature` case with `requiredTier`;
  callers use `entitlements.allows(feature)` only. Subscriptions grant only
  with a future `expirationDate` (lapse → Free, nothing deleted).
- **Paywall**: `SubscriptionStoreView` + lifetime button, shown only at Free
  limits (1 base / 10 docs / local-only / no OCR). Products:
  `molten.plus.monthly`, `molten.plus.yearly` (1-week trial),
  `molten.plus.lifetime`; Pro level reserved, not created.

### Knowledge pipeline (RAG)

```
file → SHA-256 → extract → chunk → .mkt ─┐
                                         ├→ SQLite (FTS5 + vectors) → search
              embed (e5-small) → .mkv ───┘
```

- **Process once, reuse everywhere (G4):** outputs are content-addressed by
  the source SHA-256 and written once (`CoordinatedIO.writeOnce`). Renames,
  moves, duplicates, and second devices never reprocess.
- **Extraction (K-P8):** PDFKit; Vision OCR (Plus) for pages with <50
  extractable chars and for PNG/JPEG/HEIC; UTF-8 text/code; NSAttributedString
  RTF/HTML; built-in DOCX reader (mini-ZIP + raw deflate via Compression).
- **Chunking (K-P9):** ~350 tokens, ~50 overlap, heading/paragraph-first,
  hard cap 480 incl. the "passage: " prefix; page + UTF-16 char ranges;
  token counts use the e5 tokenizer.
- **Embedding (K-E):** `intfloat/multilingual-e5-small` via MLXEmbedders,
  pinned revision, 384-dim, mean pooling with a **position-based attention
  mask** (padId is EOS — value masking would hide real tokens), L2-normalized.
  One-time download with SHA-256 verification, size shown, cellular
  confirmation on iOS (`ModelDownloadConsent`).
- **File formats (§7.3):** `.mkt` = `MKT1` + LZFSE-compressed JSON (text +
  chunks, model-independent); `.mkv` = `MKV1` + JSON header + Float16 vectors
  per profile. `manifest.json` names the active profile; vectors from other
  profiles/revisions are never ingested. `encryption` field reserved (2.1).
- **Storage (K-D4):** no database is synced. Each device builds a local
  SQLite (`knowledge.sqlite`, FTS5 + vector table) from `.mkt`/`.mkv`, with a
  local file cache (`Caches/Molten/IndexCache`) so search never depends on
  iCloud download state.
- **Retrieval (K-R):** hybrid = FTS5 BM25 top-20 + vDSP cosine top-20 merged
  by reciprocal rank fusion (k=60); keyword-only fallback without the model.
  `PromptAssembler` injects ≤8 chunks (≤3 for Apple's model) within the
  context budget, numbered `[1]…[n]` with file/page; citation chips open the
  source (Quick Look on iOS).
- **Best-device processing (K-P):** per-hash per-stage claims (10-min leases,
  60s renewal, expired takeover, 3-strikes `.failed` markers); 15-min
  heartbeats; iOS defers to a fresh Mac (<24h) unless "Process now";
  stage policy: both while charging / extract-only on battery (default) or
  always-both; `BGContinuedProcessingTask` registered in `MoltenApp.init()`.
- **iCloud (M4):** one shared container
  (`iCloud.DVGF44TKAX.com.ondemandworld.molten`), `Documents/<base>/` =
  user-visible bases, hidden `Index/` = outputs. `NSMetadataQuery` watchers;
  receiving devices only ingest finished outputs (zero processing).
  Cleanup deletes unreferenced outputs after 7 days, and defers whenever the
  local mapping is incomplete (evicted cloud files). Free→Plus moves the
  local layout into the container without reprocessing.

### Conversations (Free)

- **Search (C1):** `ConversationSearch` — SQLite FTS5 sidecar
  (`conversations.sqlite`), maintained by `SwiftDataService` on
  insert/update/delete/rename/day-delete; one-time backfill for pre-2.0
  history at launch; sidebar search jumps to the conversation.
- **Export/Import (C2):** Markdown/JSON (optional analytics) per
  conversation; zip-all via a built-in stored-ZIP writer (CRC32); JSON import.
- **Auto-titles (C3):** Apple on-device model first, active-model fallback;
  only while the conversation keeps its default name; Settings toggle;
  titles stay editable.

### Context (Free)

- `ContextWindow`: Ollama `/api/show` context length; per-server setting for
  OpenAI-compatible (default 8192); 4096 for Apple's model.
- `ContextBudget`: window split between system, Knowledge chunks, history
  (newest first; the newest message is never dropped), reply reserve
  `min(1024, window/4)`. Used by grounding and by `sendPrompt`.
- `ContextRing`: composer gauge, warnings at 80% / 95%.

### Share Extension

`MoltenShare` (iOS): `SLComposeServiceViewController` with base picker +
new-base creation; writes directly into the shared container via
`ShareImport` (testable, in the app target). macOS builds embed a
placeholder controller (share-sheet flow is iOS-only per the PRD).

## Future Enhancements

### Roadmap (PRD §13)

- **2.1:** background Mac indexing helper; iCloud chat-history sync;
  personas/prompt library; `/compact` + auto-compact; Index encryption.
- **2.2:** tool calling + MCP client (official Swift SDK); **Pro launch**.
- **2.3:** multi-model compare; branching/editing; artifacts/LaTeX/Mermaid.
- **2.4+:** Mac voice/hands-free; local memory; App Intents/Services;
  screenshot-to-panel; opt-in web search.

### Technical Debt

- Swift 6 language mode (currently Swift 5 + strict concurrency complete)
- MLX simulator support (0.32.3 crashes on simulator; device-only embedding)
- Per-message historical context-usage display

---

For questions or contributions, see [CONTRIBUTING.md](CONTRIBUTING.md) or open an issue.

