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

SwiftData handles schema migrations automatically. For manual migrations, use `ModelConfiguration`.

## UI Architecture

### Platform-Specific Views

**macOS**: `ChatView_macOS.swift`, `InputFields_macOS.swift`
**iOS**: `ChatView_iOS.swift`

**Shared**: `ChatMessageView`, `ModelSelectorView`, `SettingsView`

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
private let throttler = Throttler(delay: 0.1)
// Updates UI every 100ms instead of every chunk
```

### 2. Lazy Loading

- Models loaded on-demand
- Conversations loaded as needed
- Images loaded lazily

### 3. Efficient Data Structures

- Arrays for ordered collections
- SwiftData for persistence
- In-memory caching for frequently accessed data

### 4. Memory Management

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

### Unit Tests

- Service layer tests (mocked providers)
- Store logic tests
- Utility function tests

### Integration Tests

- End-to-end chat flow
- Model discovery
- Data persistence

### UI Tests

- User interaction flows
- Keyboard shortcuts
- Settings configuration

## Security Considerations

### Data Privacy

- All data stored locally
- No network calls except to user-configured providers
- No telemetry or analytics

### Code Signing

- Proper entitlements for macOS features
- Sandboxing where appropriate
- Secure storage for sensitive data

## Future Enhancements

### Planned Features

1. **Plugin System**: Allow custom provider implementations
2. **Advanced Analytics**: More detailed performance metrics
3. **Export/Import**: Conversation backup and restore
4. **Themes**: Customizable UI themes
5. **Accessibility**: Enhanced screen reader support

### Technical Debt

- Migrate to Swift 6 strict concurrency
- Improve error handling consistency
- Add comprehensive test coverage
- Performance profiling and optimization

---

For questions or contributions, see [CONTRIBUTING.md](CONTRIBUTING.md) or open an issue.

