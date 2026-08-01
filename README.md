# Molten

**Local AI. On Your Terms.**

Molten is a privacy-first macOS, iOS, and iPadOS app that runs local LLMs — Ollama, any OpenAI API-compatible server (such as oMLX or Swama), or Apple Foundation Models — completely offline, completely yours.

![Swift](https://img.shields.io/badge/swift-5.9+-F54A2A?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-26.0+-000000?logo=apple&logoColor=white)
![iPadOS](https://img.shields.io/badge/iPadOS-26.0+-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)

## 🌟 Key Differentiators

✅ **Mac-first native app** - Not a web wrapper like Open WebUI  
✅ **Multi-backend support** - Ollama (native API) + any OpenAI-compatible server (oMLX, Swama, …) + Apple Foundation Models, in one app  
✅ **Privacy obsessed** - Local-only by design, not bolted-on  
✅ **MLX optimized** - Leverage Apple Silicon for speed  
✅ **Indie positioning** - No corporate baggage = trust  

## 📖 Overview

Molten is a native Apple-platform application for macOS, iOS, and iPadOS. It provides an elegant, ChatGPT-like interface for interacting with locally hosted language models through multiple backends:

- **Ollama** - The popular local LLM runtime (its own native API)
- **OpenAI API-compatible servers** - Any local server that speaks the OpenAI chat completions API. Recommended on macOS:
  - **[oMLX](https://omlx.ai)** - a menu-bar LLM server for Apple Silicon (continuous batching, tiered KV caching) that serves an OpenAI-compatible API
  - **Swama** - an MLX-based inference CLI optimized for Apple Silicon
- **Apple Foundation Models** - Native on-device models (macOS 26.0+)

All processing happens locally on your device. No data leaves your device. Ever.

## ✨ Features

### Core Functionality
- **Multi-Provider Support**: Seamlessly switch between Ollama, OpenAI-compatible servers, and Apple Foundation Models — models are prefixed in the picker (`1:` Ollama, `2:` OpenAI API, `A:` Apple)
- **Streaming Responses**: Real-time streaming of model responses for instant feedback
- **Conversation Management**: Persistent conversation history with SwiftData
- **Model Selection**: Unified model picker showing all available models from all providers
- **Performance Analytics**: Server-reported metrics where the backend provides them (prompt eval rate, eval rate, throughput, tokens, total time); honest estimates otherwise

### User Experience
- **Native Apple Design**: Built with SwiftUI, feels at home on macOS, iOS, and iPadOS
- **Markdown Rendering**: Beautiful rendering of code blocks, tables, and formatted text
- **Syntax Highlighting**: Powered by Splash for code blocks
- **Dark/Light Mode**: System-aware color schemes
- **Keyboard Shortcuts**: macOS-native keyboard shortcuts (⌘⌥K for panel mode)
- **Floating Panel**: Quick access panel mode for quick interactions
- **Voice Input**: Speech-to-text for voice prompts (uses the system speech recognizer)
- **Text-to-Speech**: Read aloud functionality with system voices
- **Multimodal Support**: Text and image inputs supported

### Privacy & Security
- **100% Local**: All chat processing happens on your device; no telemetry, no tracking, no analytics
- **Offline-First**: Works completely offline once models are loaded
- **Open Source**: Full source code available for audit
- **Note on voice input**: voice transcription uses the system speech recognizer, which may process audio with Apple's speech services depending on your device and settings — everything else stays local

## 🏗️ Architecture

Molten follows a clean architecture pattern with clear separation of concerns:

### Services Layer
- **ModelProviderProtocol**: Unified streaming interface for all model providers
- **OllamaService**: Ollama native API client
- **SwamaService**: OpenAI-compatible API client (works with oMLX, Swama, and any server that implements `/v1/chat/completions` streaming)
- **AppleFoundationService**: Interface for Apple Foundation Models
- **SwiftDataService**: Actor-based data persistence
- **SpeechService**: Text-to-speech functionality
- **HapticsService**: Haptic feedback (iOS)
- **Clipboard**: Cross-platform clipboard access

### Stores (Observable State Management)
- **ConversationStore**: Manages conversations, messages, and streaming
- **LanguageModelStore**: Manages available language models from all providers
- **CompletionsStore**: Manages custom completion templates
- **AppStore**: Global app state and reachability

### Data Models
- **SwiftData Models**: `ConversationSD`, `MessageSD`, `LanguageModelSD`, `CompletionInstructionSD`
- **API Models**: `ChatMessage`, `ChatCompletionRequest/Response`, `ContentType`

### UI Architecture
- **Platform-Specific Views**: Separate implementations for macOS and iOS
- **Shared Components**: Reusable UI components across platforms
- **SwiftUI + @Observable**: Modern reactive UI framework
- **SwiftData Integration**: Automatic UI updates from data changes

## 🚀 Getting Started

### Prerequisites

1. **macOS 26.0+**, **iOS 26.0+**, **iPadOS 26.0+**
2. **Apple Silicon Mac** (M1, M2, M3, or later) - Required for Apple Foundation Models and MLX backends
3. **Xcode 26+** (for building from source)
4. **At least one backend running**:
   - Ollama (optional)
   - An OpenAI-compatible server such as oMLX or Swama (optional)
   - Apple Foundation Models (built-in on macOS 26.0+)

### Installation

#### Option 1: Download Pre-built App
Download the latest release from the [Releases](https://github.com/OnDemandWorld/molten/releases) page.

#### Option 2: Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/OnDemandWorld/molten.git
   cd molten
   ```

2. **Open in Xcode**
   ```bash
   open Molten.xcodeproj
   ```

3. **Build and Run**
   - Select the "Molten" scheme
   - Choose your target device (Mac)
   - Press ⌘R to build and run

   Builds are reproducible: package versions are pinned in the committed `Package.resolved`.

### Setting Up Backends

#### Ollama (native API)

1. **Install Ollama** (if not already installed)
   ```bash
   brew install ollama
   # or download from https://ollama.ai
   ```

2. **Start Ollama**
   ```bash
   ollama serve
   ```

3. **Pull a model**
   ```bash
   ollama pull llama2
   ```

4. **Configure in Molten**
   - Open Settings (⌘,)
   - Go to the **1. Ollama API** section
   - Enter server URL (default: `http://localhost:11434`)
   - Optional: Add Bearer Token if your server is behind an auth proxy
   - Models will auto-populate

#### OpenAI API-compatible servers (oMLX, Swama, …)

Molten connects to any local server that implements the OpenAI chat completions API (`/v1/models` and streaming `/v1/chat/completions`). Two great options on macOS:

**oMLX** ([omlx.ai](https://omlx.ai) · [github.com/jundot/omlx](https://github.com/jundot/omlx))

1. **Install oMLX** — download the `.dmg` from its Releases page, or via Homebrew:
   ```bash
   brew tap jundot/omlx https://github.com/jundot/omlx
   brew install omlx
   ```

2. **Start the server and pull models** (managed from the menu bar app or CLI):
   ```bash
   omlx start
   ```

3. **Configure in Molten**
   - Open Settings (⌘,) → **2. OpenAI API**
   - Enter server URL: `http://localhost:8000` (oMLX's default; Molten adds the `/v1` paths itself — enter the root URL, and use your `OMLX_PORT` if you changed it)
   - Optional: Add Bearer Token if you enabled oMLX API-key authentication
   - Models will auto-populate

**Swama**

1. **Install Swama** (if not already installed)
   ```bash
   # Follow Swama installation instructions
   # https://github.com/Trans-N-ai/swama
   ```

2. **Start Swama**
   ```bash
   swama serve
   ```

3. **Configure in Molten**
   - Open Settings (⌘,) → **2. OpenAI API**
   - Enter server URL (default: `http://localhost:28100`)
   - Optional: Add Bearer Token
   - Models will auto-populate

Any other OpenAI-compatible local server works the same way — point the **2. OpenAI API** URL at it.

#### Apple Foundation Models

Apple Foundation Models are built-in on macOS 26.0+ and require no setup. They will automatically appear in the model list if available on your system.

## 📖 Usage

### Basic Chat

1. **Select a Model**: Click the model selector in the header to choose from available models (`1:` Ollama, `2:` OpenAI API, `A:` Apple)
2. **Type a Message**: Enter your prompt in the text field
3. **Send**: Press ⌘↩ or click Send
4. **View Analytics**: Check the footer below each assistant message for performance metrics

### Keyboard Shortcuts

- **⌘↩**: Send message
- **⌘⌥K**: Toggle panel mode
- **⌘,**: Open Settings
- **⌘N**: New conversation
- **⌘K**: Focus search (in sidebar)

### Settings

Access Settings via ⌘, or the menu bar:

- **General Settings**
  - Default Model: Choose your preferred model (restored on relaunch)
  - System Prompt: Set default behavior for new conversations
  - Ping Interval: How often to check provider availability
    - macOS default: 15 seconds
    - iOS/iPadOS default: 30 seconds (optimized for battery life)

- **Provider Settings**
  - **1. Ollama API**: server URL and optional Bearer Token
    - Default: `http://localhost:11434` (auto-detected if not configured)
    - Leave empty to disable Ollama checking
  - **2. OpenAI API**: server URL and optional Bearer Token for any OpenAI-compatible server (oMLX, Swama, …)
    - Default: `http://localhost:28100` (auto-detected if not configured)
    - Leave empty to disable checking
  - Connection status indicators
  - **Smart Polling**: The app uses intelligent backoff strategies:
    - Default localhost: Aggressive backoff (30s → 5min) when unreachable
    - User-configured URLs: Moderate backoff (10s → 60s) when unreachable
    - Results cached for 10 seconds to minimize network requests

- **App Settings**
  - Appearance: Light/Dark/System
  - Voice: Text-to-speech voice selection
  - Initials: Your initials for chat display
  - Vibrations: Haptic feedback (iOS)

### Performance Analytics

Each completed assistant message shows (server-reported when the backend provides usage statistics, estimated otherwise):
- **Prompt Eval Rate**: How fast the model processes input (tokens/s)
- **Eval Rate**: How fast the model generates output (tokens/s)
- **Overall Throughput**: Total tokens per second
- **Total Tokens**: Prompt + completion tokens
- **Total Time**: End-to-end response time

## 🏛️ Project Structure

```
Molten/
├── Application/
│   └── MoltenApp.swift          # Main app entry point
├── Services/
│   ├── ModelProviderProtocol.swift  # Unified provider interface
│   ├── OllamaService.swift       # Ollama native API client
│   ├── SwamaService.swift        # OpenAI-compatible API client
│   ├── AppleFoundationService.swift  # Apple Foundation Models
│   ├── SwiftDataService.swift    # Data persistence
│   ├── SpeechService.swift       # Text-to-speech
│   └── ...
├── Stores/
│   ├── ConversationStore.swift   # Conversation management
│   ├── LanguageModelStore.swift  # Model management
│   ├── CompletionsStore.swift    # Completion templates
│   └── AppStore.swift            # Global app state
├── SwiftData/
│   └── Models/                   # SwiftData models
├── UI/
│   ├── macOS/                    # macOS-specific UI
│   ├── iOS/                      # iOS-specific UI
│   └── Shared/                   # Shared UI components
├── Models/                       # Business logic models
├── Helpers/                      # Utility functions
└── Extensions/                   # Swift extensions
```

## 🔧 Development

### Building

```bash
# Using Xcode
open Molten.xcodeproj

# Or using xcodebuild
xcodebuild -scheme Molten -configuration Debug
```

### Dependencies

The project uses Swift Package Manager with a committed `Package.resolved` for reproducible builds. Key dependencies:
- **Splash**: Syntax highlighting for code blocks
- **MarkdownUI**: Markdown rendering
- **KeyboardShortcuts**: macOS keyboard shortcuts
- **ActivityIndicatorView**: Loading indicators
- **OllamaKit**: Ollama API client

### Code Style

- Swift with strict concurrency checking (Swift 6-ready)
- `@Observable` for state management
- Actor pattern for thread-safe operations
- Async/await for asynchronous operations
- Comprehensive inline documentation

### Testing

```bash
# macOS
xcodebuild test -scheme Molten -destination 'platform=macOS'

# iOS Simulator
xcodebuild test -scheme Molten -destination 'platform=iOS Simulator,name=iPhone 17'
```

Unit tests live in `MoltenTests/` and cover day-deletion safety, provider request construction, prompt assembly, and analytics computation.

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code of Conduct

Please be respectful and constructive in all interactions. We're all here to build something great together.

## 📝 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Molten is based on the excellent work of the [Enchanted](https://github.com/gluonfield/enchanted) project by [Augustinas Malinauskas](https://github.com/gluonfield). We are grateful for their open-source contribution that made this project possible.

### Original Enchanted Project
- **Repository**: https://github.com/gluonfield/enchanted
- **Author**: Augustinas Malinauskas
- **License**: Apache License 2.0

### Additional Credits

- **Ollama**: Local LLM runtime - https://ollama.ai
- **oMLX**: LLM inference server for Apple Silicon with an OpenAI-compatible API - https://github.com/jundot/omlx
- **Swama**: MLX-based inference engine - https://github.com/Trans-N-ai/swama
- **MLX**: Machine learning framework for Apple Silicon - https://github.com/ml-explore/mlx
- **Splash**: Syntax highlighting - https://github.com/JohnSundell/Splash
- **MarkdownUI**: Markdown rendering - https://github.com/gonzalezreal/MarkdownUI

## 🐛 Troubleshooting

### Models Not Appearing

- **Check Provider Status**: Ensure the backend is running and reachable (Ollama, oMLX/Swama server)
- **Verify Settings**: Check server URLs in Settings
  - Leave URL fields empty to disable checking for that provider
  - Default localhost URLs are auto-detected if not configured
  - For OpenAI-compatible servers, confirm the URL points at the server's API root
- **Check Logs**: Look for connection errors in Console.app
- **Restart Providers**: Try restarting your Ollama / OpenAI-compatible servers
- **Polling Behavior**: The app uses smart backoff - if a provider is unreachable, it will check less frequently to reduce error spam

### Performance Issues

- **Apple Silicon Required**: Ensure you're using an Apple Silicon Mac
- **Check System Resources**: Monitor memory and CPU usage
- **Model Size**: Larger models require more resources
- **Close Other Apps**: Free up system resources

### Build Errors

- **Clean Build**: Product → Clean Build Folder (⇧⌘K)
- **Reset Packages**: File → Packages → Reset Package Caches
- **Xcode Version**: Ensure Xcode 26+ is installed

### Assets Missing on iOS/iPadOS

- **Check Asset Idiom**: Ensure imagesets include `universal` entries (not mac-only)
- **Target Membership**: Confirm the asset catalog is included in the iOS target

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/OnDemandWorld/molten/issues)
- **Discussions**: [GitHub Discussions](https://github.com/OnDemandWorld/molten/discussions)
- **Documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation

## 🗺️ Roadmap

- [x] iOS/iPadOS support
- [x] OpenAI-compatible server support (oMLX, Swama, …)
- [ ] Additional model providers
- [ ] Plugin system for custom providers
- [ ] Advanced conversation management
- [ ] Export/import conversations
- [ ] Custom themes
- [ ] More keyboard shortcuts
- [ ] Accessibility improvements

---

**Molten** - Local AI. On Your Terms. 🍎

Made with ❤️ for the privacy-conscious Mac user.
