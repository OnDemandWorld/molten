# Molten

**Local AI. On Your Terms.**

Molten is a privacy-first macOS, iOS, and iPadOS app that runs local LLMs—Ollama, Swama, or Apple Foundation Models—completely offline, completely yours.

![Swift](https://img.shields.io/badge/swift-5.9+-F54A2A?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.0+-000000?logo=apple&logoColor=white)
![iPadOS](https://img.shields.io/badge/iPadOS-17.0+-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)

## 🌟 Key Differentiators

✅ **Mac-first native app** - Not a web wrapper like Open WebUI  
✅ **Multi-backend support** - Ollama + Swama + Apple Models in one app  
✅ **Privacy obsessed** - Local-only by design, not bolted-on  
✅ **MLX optimized** - Leverage Apple Silicon for speed  
✅ **Indie positioning** - No corporate baggage = trust  

## 📖 Overview

Molten is a native Apple-platform application for macOS, iOS, and iPadOS. It provides an elegant, ChatGPT-like interface for interacting with locally hosted language models through multiple backends:

- **Ollama** - The popular local LLM runtime
- **Swama** - MLX-based inference engine optimized for Apple Silicon
- **Apple Foundation Models** - Native on-device models (macOS 26.0+)

All processing happens locally on your device. No data leaves your device. Ever.

## ✨ Features

### Core Functionality
- **Multi-Provider Support**: Seamlessly switch between Ollama, Swama, and Apple Foundation Models
- **Streaming Responses**: Real-time streaming of model responses for instant feedback
- **Conversation Management**: Persistent conversation history with SwiftData
- **Model Selection**: Unified model picker showing all available models from all providers
- **Performance Analytics**: Detailed metrics showing prompt eval rate, eval rate, and throughput

### User Experience
- **Native Apple Design**: Built with SwiftUI, feels at home on macOS, iOS, and iPadOS
- **Markdown Rendering**: Beautiful rendering of code blocks, tables, and formatted text
- **Syntax Highlighting**: Powered by Splash for code blocks
- **Dark/Light Mode**: System-aware color schemes
- **Keyboard Shortcuts**: macOS-native keyboard shortcuts (⌘⌥K for panel mode)
- **Floating Panel**: Quick access panel mode for quick interactions
- **Voice Input**: Speech-to-text for voice prompts
- **Text-to-Speech**: Read aloud functionality with system voices
- **Multimodal Support**: Text and image inputs supported

### Privacy & Security
- **100% Local**: All processing happens on your device
- **No Telemetry**: No tracking, no analytics, no data collection
- **Offline-First**: Works completely offline once models are loaded
- **Open Source**: Full source code available for audit

## 🏗️ Architecture

Molten follows a clean architecture pattern with clear separation of concerns:

### Services Layer
- **ModelProviderProtocol**: Unified interface for all model providers
- **OllamaService**: Handles communication with Ollama API
- **SwamaService**: Handles communication with Swama API (OpenAI-compatible)
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

1. **macOS 14.0+**, **iOS 17.0+**, **iPadOS 17.0+**
2. **Apple Silicon Mac** (M1, M2, M3, or later) - Required for Apple Foundation Models
3. **Xcode 15.0+** (for building from source)
4. **At least one backend running**:
   - Ollama (optional)
   - Swama (optional)
   - Apple Foundation Models (built-in on macOS 26.0+)

### Installation

#### Option 1: Download Pre-built App (Coming Soon)
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

### Setting Up Backends

#### Ollama

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
   - Go to "Ollama" section
   - Enter server URI (default: `http://localhost:11434`)
   - Optional: Add Bearer Token if using remote Ollama
   - Models will auto-populate

#### Swama

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
   - Open Settings (⌘,)
   - Go to "Swama" section
   - Enter server URI (default: `http://localhost:28100`)
  - Optional: Add Bearer Token
   - Models will auto-populate

#### Apple Foundation Models

Apple Foundation Models are built-in on macOS 26.0+ and require no setup. They will automatically appear in the model list if available on your system.

## 📖 Usage

### Basic Chat

1. **Select a Model**: Click the model selector in the header to choose from available models
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
  - Default Model: Choose your preferred model
  - System Prompt: Set default behavior for new conversations
  - Ping Interval: How often to check provider availability
    - macOS default: 15 seconds
    - iOS/iPadOS default: 30 seconds (optimized for battery life)

- **Provider Settings**
  - Configure Ollama server URI and Bearer Token
    - Default: `http://localhost:11434` (auto-detected if not configured)
    - Leave empty to disable Ollama checking
  - Configure Swama server URI and Bearer Token
    - Default: `http://localhost:28100` (auto-detected if not configured)
    - Leave empty to disable Swama checking
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

Each completed assistant message shows:
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
│   ├── OllamaService.swift       # Ollama API client
│   ├── SwamaService.swift        # Swama API client
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

The project uses Swift Package Manager. Key dependencies:
- **Splash**: Syntax highlighting for code blocks
- **MarkdownUI**: Markdown rendering
- **KeyboardShortcuts**: macOS keyboard shortcuts
- **ActivityIndicatorView**: Loading indicators
- **OllamaKit**: Ollama API client

### Code Style

- Swift 6 language mode with strict concurrency
- `@Observable` for state management
- Actor pattern for thread-safe operations
- Async/await for asynchronous operations
- Comprehensive inline documentation

### Testing

```bash
# Run tests
xcodebuild test -scheme Molten
```

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

- **Swama**: MLX-based inference engine - https://github.com/Trans-N-ai/swama
- **Ollama**: Local LLM runtime - https://ollama.ai
- **MLX**: Machine learning framework for Apple Silicon - https://github.com/ml-explore/mlx
- **Splash**: Syntax highlighting - https://github.com/JohnSundell/Splash
- **MarkdownUI**: Markdown rendering - https://github.com/gonzalezreal/MarkdownUI

## 🐛 Troubleshooting

### Models Not Appearing

- **Check Provider Status**: Ensure the provider is running and reachable
- **Verify Settings**: Check server URIs in Settings
  - Leave URI fields empty to disable checking for that provider
  - Default localhost URLs are auto-detected if not configured
- **Check Logs**: Look for connection errors in Console.app
- **Restart Providers**: Try restarting Ollama/Swama servers
- **Polling Behavior**: The app uses smart backoff - if a provider is unreachable, it will check less frequently to reduce error spam

### Performance Issues

- **Apple Silicon Required**: Ensure you're using an Apple Silicon Mac
- **Check System Resources**: Monitor memory and CPU usage
- **Model Size**: Larger models require more resources
- **Close Other Apps**: Free up system resources

### Build Errors

- **Clean Build**: Product → Clean Build Folder (⇧⌘K)
- **Reset Packages**: File → Packages → Reset Package Caches
- **Xcode Version**: Ensure Xcode 15.0+ is installed
- **Swift Version**: Check Swift version compatibility

### Assets Missing on iOS/iPadOS

- **Check Asset Idiom**: Ensure imagesets include `universal` entries (not mac-only)
- **Target Membership**: Confirm the asset catalog is included in the iOS target

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/OnDemandWorld/molten/issues)
- **Discussions**: [GitHub Discussions](https://github.com/OnDemandWorld/molten/discussions)
- **Documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation

## 🗺️ Roadmap

- [x] iOS/iPadOS support
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
