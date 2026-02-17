# VoiceInput

A macOS menu bar app that converts speech to text using on-device AI. Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit), all processing happens locally on your Mac — no cloud, no API keys, no data leaves your device.

## Features

- **On-device processing** — All transcription runs locally via WhisperKit + Core ML. Zero network calls.
- **Global hotkey** — Start/stop recording from any app without switching windows.
- **Multi-language support** — English, Korean, Japanese, Chinese, Spanish, French, German.
- **Smart text insertion** — Automatically types transcribed text into the active app using Accessibility API, keyboard simulation, or clipboard fallback.
- **Multiple Whisper models** — Choose the model that fits your speed/accuracy needs.
- **Menu bar app** — Lives in the menu bar, stays out of your way.
- **Apple Silicon optimized** — Runs on Core ML with Apple Neural Engine acceleration.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)

## Installation

### Download

Download the latest release from the [Releases](https://github.com/junghyunJJ/voiceinput/releases) page.

### Build from Source

```bash
# Clone the repository
git clone https://github.com/junghyunJJ/voiceinput.git
cd voiceinput

# Build
swift build

# Build and run as .app (development)
./Scripts/build-dev.sh
```

For a signed release build with notarization:

```bash
./Scripts/build-release.sh
```

## Usage

1. **Launch** — VoiceInput appears as an icon in the menu bar.
2. **Grant permissions** — Allow Microphone and Accessibility access when prompted.
3. **Record** — Click the menu bar icon or use the global hotkey to start recording. Speak, then stop recording — the transcribed text is automatically inserted at your cursor.
4. **Select a model** — Open Settings from the menu bar to download and switch between models.

### Available Models

| Model | Size | Speed | Accuracy | Best for |
|-------|------|-------|----------|----------|
| tiny | ~40 MB | Fastest | Basic | Quick notes, simple phrases |
| base | ~75 MB | Fast | Good | Everyday use |
| small | ~250 MB | Moderate | Better | General purpose (default) |
| large-v3 | ~1.5 GB | Slower | Best | Maximum accuracy |

## Permissions

VoiceInput requires two macOS permissions:

- **Microphone** — To capture audio for transcription.
- **Accessibility** — To type transcribed text into the active application.

Both permissions are requested on first launch and can be managed in System Settings > Privacy & Security.

## Project Structure

```
VoiceInput/
├── Package.swift                 # Swift Package Manager manifest
├── Package.resolved              # Dependency lock file
├── Scripts/
│   ├── build-dev.sh              # Development build & launch
│   └── build-release.sh          # Release build, sign, notarize, DMG
├── VoiceInput/
│   ├── App/
│   │   ├── VoiceInputApp.swift       # App entry point
│   │   └── AppDelegate.swift         # NSApplicationDelegate
│   ├── Models/
│   │   ├── AppSettings.swift         # User preferences
│   │   └── RecordingState.swift      # Recording state machine
│   ├── Services/
│   │   ├── Audio/
│   │   │   ├── AudioService.swift    # Microphone capture
│   │   │   └── AudioBuffer.swift     # Audio sample buffer
│   │   ├── TextInsertion/
│   │   │   ├── TextInsertionManager.swift   # Insertion strategy coordinator
│   │   │   ├── AccessibilityInserter.swift  # AX API insertion
│   │   │   ├── KeyboardSimulator.swift      # CGEvent key simulation
│   │   │   └── ClipboardInserter.swift      # Clipboard fallback
│   │   ├── Transcription/
│   │   │   ├── TranscriptionEngine.swift    # Engine protocol
│   │   │   ├── WhisperKitEngine.swift       # WhisperKit implementation
│   │   │   └── TranscriptionResult.swift    # Result model
│   │   ├── HotkeyManager.swift       # Global hotkey registration
│   │   ├── ModelManager.swift         # Model download & management
│   │   └── PermissionsManager.swift   # Permission checks
│   ├── ViewModels/
│   │   └── AppViewModel.swift        # Main view model
│   ├── Views/
│   │   ├── MenuBarView.swift         # Menu bar UI
│   │   ├── SettingsView.swift        # Settings window
│   │   ├── OnboardingView.swift      # First-launch setup
│   │   └── RecordingOverlayView.swift # Recording indicator overlay
│   ├── Utilities/
│   │   └── Constants.swift           # App-wide constants
│   └── Resources/
│       ├── Info.plist                # App metadata
│       └── VoiceInput.entitlements   # Sandbox entitlements
└── VoiceInputTests/
    ├── AudioBufferTests.swift
    ├── RecordingStateTests.swift
    └── TranscriptionResultTests.swift
```

## Tech Stack

- **Language**: Swift 5.9
- **UI**: SwiftUI + AppKit (menu bar)
- **Speech-to-Text**: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML)
- **Build System**: Swift Package Manager
- **Minimum Target**: macOS 14.0

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax — On-device speech recognition for Apple Silicon
- [Whisper](https://github.com/openai/whisper) by OpenAI — The model architecture behind the transcription
