# Repository Guidelines

Molten is a native SwiftUI app (macOS/iOS/iPadOS) providing a chat UI for local LLMs: Ollama, OpenAI-compatible servers (Swama/oMLX), and Apple Foundation Models. All processing is local. See `ARCHITECTURE.md` for the design doc.

## Project Structure & Module Organization

- `Molten/` — app source (single Xcode project `Molten.xcodeproj`, scheme/target `Molten`):
  - `Application/` — `MoltenApp.swift` is the real `@main`; `EnchantedApp.swift` is a legacy duplicate not in the build target — don't edit.
  - `Stores/` — `@Observable` state (`ConversationStore`, `AppStore`, …).
  - `Services/` — providers implementing `ModelProviderProtocol` (`OllamaService`, `SwamaService`, `AppleFoundationService`) plus `SwiftDataService`, an actor owning the only `ModelContext`.
  - `SwiftData/Models/` — persistence models (`ConversationSD`, `MessageSD`, …).
  - `UI/Shared/`, `UI/macOS/`, `UI/iOS/` — `Shared/` code must compile for both platforms.
- `MoltenTests/` — XCTest suite. `scripts/release.sh` — release tooling. Repo-root APP_STORE_*/SUBMISSION_* docs are release process, not dev docs.

## Build, Test, and Development Commands

The target is multi-platform, so **always pass a destination**:

```bash
xcodebuild -scheme Molten -destination 'platform=macOS' build                  # build macOS
xcodebuild -scheme Molten -destination 'platform=iOS Simulator,name=iPhone 16' build  # build iOS
xcodebuild test -scheme Molten -destination 'platform=macOS'                   # run tests
```

Deployment targets are macOS 26.0 / iOS 26.0 with `SWIFT_STRICT_CONCURRENCY = complete` — new code must compile under strict concurrency.

## Coding Style & Naming Conventions

- Follow Swift API Design Guidelines; prefer `async/await`, `@Observable`, `final` classes. No lint/format tooling configured.
- Naming: types PascalCase, members camelCase, files match their type. Suffixes: `Store`, `Service`, and `SD` for SwiftData models.
- New services follow the `static let shared` singleton pattern (only `ConversationStore` is injected). Use `// MARK:` sections and doc comments on public APIs.

## Testing Guidelines

- Framework: XCTest with `@testable import Molten`; files named `<Domain>Tests.swift`, methods `test<Behavior>` (e.g., `AnalyticsTests.swift`).
- Use `SwiftDataService(inMemory: true)` for persistence tests; mock providers/network. Run via the `xcodebuild test` command above or ⌘U.

## Commit & Pull Request Guidelines

- History uses conventional-style messages with scopes/issue refs: `feat(ui): …`, `fix(F-52): …`, `chore: …`, `docs(README): …`. Imperative mood.
- One focused change per PR with a clear description and linked issues; one review required. Include screenshots for UI changes and confirm builds pass on both macOS and iOS destinations.

## Gotchas

- Never create additional `ModelContext`s — route all SwiftData access through `SwiftDataService`.
- Streaming chunks are buffered through a `Throttler` (~0.15 s); don't remove it (UI freezes).
- Shared asset imagesets need `universal` idioms or they won't render on iOS.
- A built `Molten.app` is checked in at the repo root — leave it alone unless updating a release artifact.
