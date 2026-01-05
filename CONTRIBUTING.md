# Contributing to Molten

Thank you for your interest in contributing to Molten! This document provides guidelines and instructions for contributing.

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Respect different viewpoints and experiences

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/yourusername/molten/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - System information (macOS version, hardware)
   - Relevant logs or screenshots

### Suggesting Features

1. Check if the feature has already been suggested
2. Open a new issue with:
   - Clear description of the feature
   - Use case and motivation
   - Potential implementation approach (if you have ideas)

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
   - Follow the code style guidelines
   - Add tests if applicable
   - Update documentation
4. **Commit your changes**
   ```bash
   git commit -m "Add: Description of your feature"
   ```
   Use clear, descriptive commit messages
5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Open a Pull Request**
   - Provide a clear description
   - Reference any related issues
   - Wait for review and feedback

## Development Setup

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 15.0+
- Apple Silicon Mac (for running)
- Git

### Setup Steps

1. **Clone your fork**
   ```bash
   git clone https://github.com/yourusername/molten.git
   cd molten
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/originalusername/molten.git
   ```

3. **Open in Xcode**
   ```bash
   open Molten.xcodeproj
   ```

4. **Build the project**
   - Select the "Molten" scheme
   - Press ⌘R to build and run

## Code Style Guidelines

### Swift Style

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use Swift 6 language mode
- Prefer `async/await` over completion handlers
- Use `@Observable` for state management
- Mark classes as `final` when not meant for subclassing

### Naming Conventions

- **Types**: PascalCase (`ConversationStore`, `ChatMessage`)
- **Functions**: camelCase (`sendPrompt`, `loadModels`)
- **Variables**: camelCase (`conversationState`, `selectedModel`)
- **Constants**: camelCase for local, PascalCase for global
- **Files**: Match type names (`ConversationStore.swift`)

### Documentation

- Add header comments to all files
- Document public APIs with doc comments
- Use `// MARK:` to organize code sections
- Explain complex logic with inline comments

### Example

```swift
/// Manages conversation state and message streaming.
/// 
/// This store coordinates between model providers and the UI,
/// handling streaming responses and analytics tracking.
@Observable
final class ConversationStore {
    // MARK: - Properties
    
    /// Current conversation state (loading, completed, error)
    @MainActor var conversationState: ConversationState = .completed
    
    // MARK: - Methods
    
    /// Sends a prompt to the selected model provider
    /// - Parameters:
    ///   - userPrompt: The user's message text
    ///   - model: The language model to use
    ///   - image: Optional image attachment
    ///   - systemPrompt: Optional system prompt for new conversations
    @MainActor
    func sendPrompt(
        userPrompt: String,
        model: LanguageModelSD,
        image: Image? = nil,
        systemPrompt: String = ""
    ) {
        // Implementation
    }
}
```

## Testing

### Writing Tests

- Add unit tests for business logic
- Test edge cases and error conditions
- Mock external dependencies (providers, network)

### Running Tests

```bash
# In Xcode: ⌘U
# Or via command line:
xcodebuild test -scheme Molten
```

## Project Structure

When adding new code:

- **Services**: Add to `Molten/Services/`
- **Stores**: Add to `Molten/Stores/`
- **UI Components**: Add to `Molten/UI/Shared/` or platform-specific folders
- **Models**: Add to `Molten/Models/` or `Molten/SwiftData/Models/`
- **Helpers**: Add to `Molten/Helpers/`
- **Extensions**: Add to `Molten/Extensions/`

## Commit Message Format

Use clear, descriptive commit messages:

```
Add: Feature description
Fix: Bug description
Refactor: What was refactored
Docs: Documentation update
Style: Code style changes
Test: Test additions/changes
```

Examples:
- `Add: Support for custom model providers`
- `Fix: Memory leak in ConversationStore`
- `Refactor: Extract analytics logic to separate service`
- `Docs: Update README with new features`

## Review Process

1. All PRs require at least one review
2. Address review comments promptly
3. Keep PRs focused (one feature/fix per PR)
4. Keep PRs small when possible (easier to review)

## Questions?

- Open an issue for questions
- Check existing documentation
- Ask in discussions

Thank you for contributing to Molten! 🎉

