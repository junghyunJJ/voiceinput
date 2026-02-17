# Contributing to VoiceInput

Thank you for your interest in contributing to VoiceInput! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/your-username/voiceinput.git
   cd voiceinput
   ```
3. Create a branch for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Xcode 16+ (or Swift 5.9+ toolchain)

### Building

```bash
# Build the project
swift build

# Build and run as .app (creates signed bundle in ~/Applications)
./Scripts/build-dev.sh
```

### Testing

```bash
# Tests require Xcode (XCTest is not available in Command Line Tools)
xcodebuild test -scheme VoiceInput -destination 'platform=macOS'
```

## How to Contribute

### Reporting Bugs

- Open an [issue](https://github.com/junghyunJJ/voiceinput/issues) with a clear title and description.
- Include your macOS version, Mac model, and steps to reproduce.

### Suggesting Features

- Open an issue with the `enhancement` label.
- Describe the use case and expected behavior.

### Pull Requests

1. Make sure your code builds without errors (`swift build`).
2. Keep changes focused — one feature or fix per PR.
3. Write clear commit messages.
4. Update documentation if your changes affect usage.
5. Open a pull request against the `main` branch.

## Code Style

- Follow standard Swift conventions and the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use `@MainActor` for UI-related code.
- Prefer `async/await` over callbacks.
- Use `enum` namespaces for constants (see `Constants.swift`).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
