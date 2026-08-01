# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Molten is a native SwiftUI app for macOS, iOS, and iPadOS that provides a chat UI for locally hosted LLMs. It supports three backends: **Ollama**, **Swama** (MLX-based, OpenAI-compatible API), and **Apple Foundation Models** (macOS 26+). All processing is local; there is no telemetry. The project is a fork of [Enchanted](https://github.com/gluonfield/enchanted) (Apache 2.0) — some file headers still credit the original author.

## Build & Run

Single multi-platform Xcode project (`Molten.xcodeproj`), one target `Molten`, one shared scheme `Molten`. The target builds for `macosx`, `iphonesimulator`, and `iphoneos`, so **always pass a destination** when building from the command line:

```bash
# macOS
xcodebuild -scheme Molten -configuration Debug -destination 'platform=macOS' build

# iOS Simulator
xcodebuild -scheme Molten -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build

# Resolve SPM packages without building
xcodebuild -resolvePackageDependencies -scheme Molten
```

Deployment targets are **macOS 26.0 / iOS 26.0** (per `project.pbxproj`; the README's older 14.0/17.0 figures are outdated). Swift language mode is 5.0 with `SWIFT_STRICT_CONCURRENCY = complete` (Swift 6-ready), so new code must compile under strict concurrency.

### Tests

There is **no test target** in this project — `xcodebuild test` and ⌘U have nothing to run. If adding tests, a new test target must be created in the Xcode project first. There is no lint/format tooling configured.

### Dependencies (SPM)

OllamaKit, Splash (syntax highlighting), swift-markdown-ui (MarkdownUI), KeyboardShortcuts, Magnet, ActivityIndicatorView, Vortex, WrappingHStack, swift-async-algorithms.

## Architecture

Layered: **UI (SwiftUI) → Stores (`@Observable`) → Services → SwiftData**. See `ARCHITECTURE.md` for the long-form version.

### Wiring

- `MoltenApp` (`@main`, in `Application/MoltenApp.swift`) → `ApplicationEntry`, which switches on `AppStore.appState` between the `Chat` and `Voice` scenes.
- Services and stores are global singletons (`static let shared`, mostly `nonisolated(unsafe)`), not injected — except `ConversationStore`, which takes its `SwiftDataService` via initializer. When adding a service, follow the `.shared` singleton pattern already in use.
- `ApplicationEntry.task` loads models, conversations, and completions on launch.

### Model provider system

`ModelProviderProtocol` (in `Services/`) is the unified interface: `reachable()`, `getModels()`, and `chatStream(...) -> AsyncThrowingStream<ChatCompletionResponse, Error>`. Three implementations, all normalizing to `ChatCompletionResponse`:

- **OllamaService** — uses OllamaKit; converts Combine publishers to `AsyncThrowingStream`.
- **SwamaService** — OpenAI-compatible API with hand-rolled SSE parsing.
- **AppleFoundationService** — `LanguageModelSession` from the FoundationModels framework; simulates streaming by chunking (macOS 26+ only, guard with availability).

Provider dispatch is a switch on the model's `modelProvider` enum (`ModelProvider`: `.ollama / .swama / .appleFoundation`) in `ConversationStore.getProvider(for:)`. Models carry a display prefix per provider (O:/S:/A: via `ModelProvider.displayPrefix`).

Provider config priority: explicit URL argument → UserDefaults → default localhost (`http://localhost:11434` Ollama, `http://localhost:28100` Swama). **An explicitly empty URL disables that provider** (`reachable()` returns false without any network call).

### Chat streaming pipeline

`ConversationStore` is the core orchestrator (`@Observable`, `@unchecked Sendable`, UI state marked `@MainActor`):

```
sendPrompt() → provider.chatStream() → handleReceive() → handleComplete()
```

- Stream chunks are appended to an **array buffer** (not string concatenation — deliberate O(n) vs O(n²) fix) and flushed to the message through a `Throttler` (~0.15s) because unthrottled SwiftUI updates can freeze the UI.
- `generationTask` holds the active stream `Task` and is how Stop/cancellation works — cancel it, don't just drop references.
- `handleComplete()` computes analytics (prompt eval rate, eval rate, tokens, timing) stored on `MessageSD`, then persists via `SwiftDataService`.

### Persistence

`SwiftDataService` is an **actor** that owns its own `ModelContainer`/`ModelContext` (autosave disabled, serial model executor) — do not create other `ModelContext`s; route all reads/writes through this service. SwiftData models (`SwiftData/Models/`): `ConversationSD`, `MessageSD`, `LanguageModelSD` (unique name, cascade-deletes its conversations), `CompletionInstructionSD`.

### Reachability polling

`AppStore` runs a timer that pings all providers, with a 10s result cache and exponential backoff when unreachable: aggressive for default localhost (30s→300s), moderate for user-configured URLs (10s→60s). Default ping interval differs by platform (macOS 15s, iOS 30s). All reachability checks use a 2s timeout. Preserve these behaviors when touching polling logic.

### UI layout

- `UI/Shared/` — cross-platform views (Chat, Sidebar, Settings, Voice, chat message components incl. Markdown/code-block rendering).
- `UI/macOS/` — macOS-only: floating PromptPanel (`PanelManager` is the `NSApplicationDelegateAdaptor` on `MoltenApp`), menu bar control, completions editor, Menus. ⌘⌥K toggles panel mode via the KeyboardShortcuts package.
- `UI/iOS/` — iOS-only chat view.
- Shared code uses `#if os(macOS)` conditionals heavily; anything added to `UI/Shared/` must compile for both platforms. Shared asset catalog imagesets must include `universal` idioms or they won't render on iOS.

## Gotchas

- `Application/EnchantedApp.swift` is a **legacy duplicate** of `MoltenApp.swift` that is *not* part of the build target (it would fail with two `@main`s if it were). Don't edit it expecting effects; the real entry point is `MoltenApp.swift`.
- The repo root contains many release/App Store process docs (`APP_STORE_*.md`, `GITHUB_RELEASE_*.md`, `SUBMISSION_*.md`, etc.) and a version-baked `scripts/release.sh` — these are release tooling, not day-to-day dev docs.
- A built `Molten.app` bundle is checked in at the repo root; leave it alone unless explicitly updating a release artifact.
- `.gitignore` excludes `QWEN.md` ("AI Assistant Context") — AI-assistant context files other than this one are intentionally kept out of the repo.
