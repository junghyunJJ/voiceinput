# VoiceInput

A macOS menu bar app that converts speech to text using on-device AI. Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit), all processing happens locally on your Mac — no cloud, no API keys, no data leaves your device.

## Features

- **On-device processing** — All transcription runs locally via WhisperKit + Core ML. Zero network calls.
- **Global hotkey** — Start/stop recording from any app without switching windows.
- **Multi-language support** — English, Korean, Japanese, Chinese, Spanish, French, German.
- **Smart text insertion** — Automatically types transcribed text into the active app using Accessibility API, keyboard simulation, or clipboard fallback.
- **Local post-processing** — Apply glossary terms, correction rules, confidence-gated candidate corrections, and deterministic output presets without sending text to a cloud service.
- **Multiple Whisper models** — Choose the model that fits your speed/accuracy needs.
- **Menu bar app** — Lives in the menu bar, stays out of your way.
- **Apple Silicon optimized** — Runs on Core ML with Apple Neural Engine acceleration.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)

## Installation

### 1. Download (Recommended)

Most users should install from the [Releases](https://github.com/junghyunJJ/voiceinput/releases) page.

### 2. Build from Source

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
3. **Download your first model** — Open **Settings > Model** and click **Download** on the model you want.
4. **Activate model** — After download, click **Use** for that model.
5. **Record** — Click the menu bar icon or use the global hotkey to start recording. Speak, then stop recording — the transcribed text is automatically inserted at your cursor.
6. **Tune output** — In **Settings > Output**, add glossary terms (names, acronyms, English product words), add correction rules for repeat ASR misses such as `chat gp t -> ChatGPT`, and choose a preset such as **Verbatim**, **Polished Message**, **Email Draft**, or **Meeting Notes**.

> Note: Internet is required only for the first model download.

## iPhone (MVP)

The repository now includes an iOS host app + custom keyboard extension.

### Generate Project

```bash
./Scripts/generate-xcode-project.sh
```

This creates `VoiceInputMobile.xcodeproj` from `project.yml`.

### Build / Test (iOS)

```bash
# Build app + embedded keyboard extension
xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination 'generic/platform=iOS Simulator' build

# Run iOS tests (settings sync + recording state + sanity checks) on the preferred simulator
DESTINATION="$(./Scripts/resolve-ios-simulator.sh --preferred "iPhone 17" --allow-fallback --destination)"
xcodebuild -project VoiceInputMobile.xcodeproj -scheme VoiceInputiOS -destination "$DESTINATION" test
```

### Capture QA Screenshots (Simulator)

Use the debug-only QA routes to capture deterministic iPhone screenshots for the gallery home screen, each host state, and the keyboard gallery:

```bash
./Scripts/capture-ios-qa-gallery.sh
```

Useful options:

```bash
./Scripts/capture-ios-qa-gallery.sh --simulator "iPhone 17" --out /tmp/voiceinput-qa
./Scripts/capture-ios-qa-gallery.sh --simulator "iPhone 17" --allow-fallback --out /tmp/voiceinput-qa
./Scripts/capture-ios-qa-gallery.sh --skip-build --out /tmp/voiceinput-qa
```

The script:

- regenerates `VoiceInputMobile.xcodeproj`
- builds the dedicated debug-only QA simulator app (`VoiceInputiOSQA`) unless `--skip-build` is passed
- forces a stable simulator status bar
- waits for a debug-only QA ready token and screen identifier from the launched app before each screenshot, instead of relying on a fixed post-launch sleep
- captures:
  - `qa-gallery-home.png`
  - `qa-host-<state>.png` for all seeded host states
  - `qa-keyboard-gallery.png`

The production `VoiceInputiOS` target no longer carries the QA gallery/readiness sources. Those routes now live behind the separate `VoiceInputiOSQA` app target used only for simulator snapshot capture.

### Verify QA Snapshots (Simulator)

Use the checked-in reference set to verify that the gallery, keyboard gallery, and seeded host states still render identically:

```bash
./Scripts/verify-ios-qa-gallery.sh
```

Refresh the baseline intentionally after an approved UI change:

```bash
./Scripts/verify-ios-qa-gallery.sh --record
```

Useful options:

```bash
./Scripts/verify-ios-qa-gallery.sh --simulator "iPhone 17"
./Scripts/verify-ios-qa-gallery.sh --simulator "iPhone 17" --allow-fallback --baseline-dir /tmp/alt-baseline
./Scripts/verify-ios-qa-gallery.sh --baseline-dir docs/qa-baselines/ios --keep-capture
```

The checked-in baseline set lives in `docs/qa-baselines/ios` and includes:

- `manifest.sha256` for expected rendered-pixel hashes
- `environment.env` for the expected `Xcode`, simulator name, exact iOS runtime, and pixel-hash mask policy

QA pixel hashing intentionally ignores the bottom `40` pixels of each screenshot. That strip is the simulator-managed home indicator overlay, not app content, and it was the only remaining non-deterministic region after the explicit ready signal landed.

`./Scripts/verify-ios-qa-gallery.sh` now runs an environment preflight before capture when that baseline contract is present, so a toolchain/runtime drift fails early with a clear mismatch instead of only showing a later snapshot diff.
When `docs/qa-baselines/ios/environment.env` is present, the checked-in verify flow is baseline-locked: wrapper-level simulator/runtime/fallback overrides are rejected instead of silently changing the reference environment.
By default, QA verification fails closed if the preferred simulator or expected runtime is unavailable. Use `--allow-fallback` only for non-baseline flows where a substitute device is acceptable.

If you intentionally move the snapshot baseline to a new Xcode/runtime pair:

```bash
./Scripts/verify-ios-qa-gallery.sh --record
```

That refreshes both the PNG baselines and `docs/qa-baselines/ios/environment.env` for the current machine.

### CI (iOS QA)

Run the same iOS CI entrypoint locally:

```bash
./Scripts/ci-verify-ios.sh
```

This script:

- runs `./Scripts/preflight-ios-qa-environment.sh` against the checked-in baseline contract
- regenerates `VoiceInputMobile.xcodeproj`
- resolves one simulator for the full run
- runs `xcodebuild test` for `VoiceInputiOS`
- reuses the same derived data for `./Scripts/verify-ios-qa-gallery.sh --skip-build`

The repo also includes a pinned GitHub Actions workflow at `.github/workflows/ci.yml` that runs:

- `swift build`
- `swift test`
- `./Scripts/ci-verify-ios.sh`

On iOS QA failure, the workflow uploads the QA capture directory and logs from `.artifacts/ios-ci`.
That artifact set now includes `logs/preflight-ios-qa-environment.log`.
Like the local verify wrapper, `./Scripts/ci-verify-ios.sh` treats the checked-in baseline as authoritative and rejects conflicting simulator/runtime/fallback overrides.

### Build / Install (Physical iPhone)

```bash
# Preferred: Team is auto-detected if already configured in Xcode
./Scripts/run-ios-device-verification.sh <DEVICE_ID_OR_NAME>

# Optional: pass team explicitly
./Scripts/run-ios-device-verification.sh <TEAM_ID> <DEVICE_ID_OR_NAME>
```

### Device Launch Troubleshooting

If install succeeds but launch fails with security messages like
`invalid code signature`, `inadequate entitlements`, or
`profile has not been explicitly trusted by the user`:

1. Unlock iPhone and open `VoiceInputiOS` once from Home Screen.
2. Approve any trust prompt.
3. Ensure `Settings > Privacy & Security > Developer Mode` is enabled.
4. Ensure `Settings > General > VPN & Device Management` trusts your developer app identity.
   - If shown, tap `Allow & Restart`, then unlock after reboot.
5. Keep iPhone online while trusting (`https://ppq.apple.com` must be reachable for trust verification).
6. If still blocked:
   - `Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy`
   - reconnect cable and trust computer again.
7. Re-run:
   ```bash
   ./Scripts/run-ios-device-verification.sh <DEVICE_ID_OR_NAME>
   ```

### iPhone Setup

1. Install and run `VoiceInputiOS` on iPhone.
2. Grant microphone permission in iOS Settings when prompted.
3. Enable keyboard: `Settings > General > Keyboard > Keyboards > Add New Keyboard > VoiceInput`.
4. Enable `Allow Full Access` for the VoiceInput keyboard.
5. In `VoiceInputiOS`, add glossary terms for names, acronyms, and mixed-language phrases you want preserved.
6. Add correction rules in `VoiceInputiOS` for phrases Whisper repeatedly hears wrong, such as `fig ma -> Figma` or `chat gp t -> ChatGPT`.
7. Add candidate corrections in `VoiceInputiOS` when you want confidence-gated local rewrites instead of an always-on exact correction.
8. Quick mode: use Apple dictation first, then switch to the VoiceInput keyboard and tap the left action button to apply your selected preset in place.
9. Pro mode: tap `Open App for Pro Dictation`, speak in the iPhone app, then tap `Stop & Transcribe`.
10. Review or edit the draft in `VoiceInputiOS`. The app now shows a compact `Paste Last Uses` preview so you can compare the current draft with the saved keyboard result.
11. If `Suggested Fixes` appear, treat them as an optional review step before returning to the keyboard. `Apply in App` updates both the draft and what `Paste Last` will use.
12. If you change the draft manually, tap `Update Paste Last` to commit the new draft for keyboard use. `Copy Saved Result` stays export-only and does not change the draft or saved keyboard state.
13. Return to the VoiceInput keyboard and tap `Paste Last` if you want to insert the saved Pro-mode transcription. When a saved result is ready, the keyboard surfaces `Paste Last` as the primary action.
14. The keyboard extension does not request microphone permission; recording happens only in the iPhone app.

### Output Presets

- **Verbatim** — Keep the raw transcript unchanged except for glossary replacements.
- **Casual Message** — Condense spacing and lightly normalize sentence casing.
- **Polished Message** — Clean spacing, capitalize the first sentence, and ensure ending punctuation.
- **Email Draft** — Wrap the cleaned transcript in a simple email scaffold.
- **Meeting Notes** — Turn sentence fragments into a local bullet list.

### Glossary

Use **Settings > Output** on macOS to add glossary entries for:

- names
- acronyms
- product terms
- mixed Korean/English phrases

Glossary aliases are matched locally across common separator variants such as `open ai`, `open-ai`, `open.ai`, plus attached Korean/Japanese particles such as `open ai에서` and `open aiで`. Common English variants are inferred automatically from the canonical phrase or replacement, so you usually do not need to type every alias by hand. Both glossary editors also show a compact `Suggested aliases` preview without persisting those inferred values.

The same local inference also normalizes compact model names such as `GPT4o` / `GPT-4o` / `GPT 4o`, `A17Pro` / `A17 Pro` / `A17-Pro`, and compact qualifier forms like `M2Ultra` / `M2-Ultra` / `M2 Ultra`, `X1Mini` / `X1-Mini` / `X1 Mini`, and `R1Air` / `R1-Air` / `R1 Air` without collapsing them to truncated family names like `GPT-4`, `A17`, or `M2`.

Exact dotted model versions such as `Claude3.7` / `Claude-3.7` / `Claude 3.7` and `Llama3.2` / `Llama-3.2` / `Llama 3.2` are normalized the same way, while broader family labels like `Claude 3` remain untouched.
Exact full variants such as `Claude3.7Sonnet` / `Claude-3.7-Sonnet` / `Claude 3.7 Sonnet` and `Llama3.2Instruct` / `Llama-3.2-Instruct` / `Llama 3.2 Instruct` are also normalized locally without collapsing to `Claude 3.7`, `Claude 3`, or other labels.
That same exact full-variant path also covers labels such as `Opus`, `Haiku`, `Vision`, and `Turbo` across attached, spaced, and hyphenated forms.

The glossary editors also include local search across phrase, replacement, explicit aliases, and suggested aliases.
When a row matches the current search, the editors show a compact explanation of which field matched.
The `Matched on` chips also highlight the exact substring that satisfied the current query.

The same shared glossary and preset schema is used by the macOS app, the iPhone host app, and the iPhone keyboard helper flow.

### Corrections

Use correction rules when the model repeatedly hears a known phrase wrong and you want a deterministic local replacement.

- `chat gp t` -> `ChatGPT`
- `fig ma` -> `Figma`
- `open a eye` -> `OpenAI`

Corrections are shared across the macOS app, the iPhone host app, and the iPhone keyboard helper flow through the same shared settings schema. They run locally before preset formatting, so Quick mode and Pro mode apply the same replacements.
Both correction editors also support local search across heard phrases and replacements.

### Candidate Corrections

Use candidate corrections when the model is usually close but you only want the rewrite to auto-apply above a confidence threshold.

- source text
- optional source aliases
- replacement text
- candidate confidence
- auto-apply policy (`Never`, `Always`, or `Threshold`)
- optional evidence note for why the local rule exists

Candidate corrections are now editable in both the macOS Output settings and the iPhone host app. They are shared through the same local settings schema as glossary terms and exact corrections, so macOS transcription, iPhone Pro mode, and keyboard helper flows all evaluate the same confidence-gated rules. A single candidate rule can also carry multiple source aliases when the same term is misheard in several ways. They match common separator variants such as `chat-gp-t` for a canonical source like `chat gp t`, and replacement-side acronym inference can cover spoken forms such as `chat g p t`, `chat 지피티`, and `chat ジーピーティー` without requiring you to duplicate every alias by hand. That inference is intentionally narrower than glossary search/preview: it does not treat the already normalized canonical replacement text as a fresh source alias, so explicit corrections still win once text is already normalized. Candidate rules also preserve conservative Korean/Japanese particle attachments such as `에서` and `で` without rewriting ordinary words like `에러` or `のり`. When a candidate stays below the auto-apply threshold, the macOS menu bar app and iPhone host app now surface it as a manual suggestion. Manual suggestions that lead to the same corrected output are collapsed in shared core even when their visible source spans overlap, while genuinely different replacements and distinct non-overlapping occurrences still remain visible. Those manual suggestions can also be promoted into an always-on local rule with `Save as Rule`, which upgrades the stored candidate correction to `Always`, keeps the canonical source when available, and learns the currently visible mixed-language form as an alias. On macOS, `Apply to App` only repairs the last successful Accessibility-based insertion, and it fails closed if the target field text has changed or the insertion originally fell back to keyboard/clipboard input. When in-place repair is unavailable, the menu bar offers `Copy Corrected Text` as an explicit clipboard-only fallback instead of mutating the active app. On iPhone, `Apply in App` remains a local draft edit, while `Update Paste Last` explicitly commits the current draft for keyboard insertion and `Copy Corrected Text` stays a separate export-only convenience action.

### Privacy (iOS)

- Transcription is local-first (on-device WhisperKit runtime).
- Audio is captured only during active recording in the iPhone app and not retained by default.
- Shared App Group storage keeps only settings and latest transcription/quick-note history.

### Default Shortcuts

- **Recording:** `Option + Space` (global)
- **Copy Last Transcription:** `Command + Shift + C` (global)

### Recording Modes

- **Toggle** — Press once to start recording, press again to stop.
- **Push-to-Talk** — Hold the shortcut to record, release to stop.

### Change Shortcuts / Mode

1. Open menu bar icon > **Settings...** > **General**
2. In **Hotkey**, click a shortcut field and press your new key combination
3. Choose **Toggle** or **Push-to-Talk**

### Model Download Progress

- While downloading, progress is shown in **Settings > Model** and also in the menu bar panel.
- The app shows both progress bar and percentage.

### Available Models

| Model | Size | Speed | Accuracy | Best for |
|-------|------|-------|----------|----------|
| tiny | ~40 MB | Fastest | Basic | Quick notes, simple phrases |
| base | ~75 MB | Fast | Good | Everyday use |
| small | ~250 MB | Moderate | Better | General purpose (default) |
| large-v3 | ~1.5 GB | Slower | Best | Maximum accuracy |

> For the highest transcription accuracy, we recommend **large-v3**.

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
│   ├── build-release.sh          # Release build, sign, notarize, DMG
│   ├── capture-ios-qa-gallery.sh # Capture deterministic iPhone QA screenshots from the simulator
│   ├── ci-verify-ios.sh          # Shared local/CI iOS test + QA snapshot verification entrypoint
│   ├── describe-ios-qa-environment.sh # Print the current Xcode/simulator/runtime contract for QA baselines
│   ├── generate-xcode-project.sh # Generate iOS Xcode project via xcodegen
│   ├── hash-png-pixels.swift     # Hash rendered PNG pixels for deterministic QA snapshot verification
│   ├── preflight-ios-qa-environment.sh # Fail early when the active iOS QA environment drifts from the baseline contract
│   ├── resolve-ios-simulator.sh  # Resolve a deterministic iPhone simulator name/UDID/destination
│   ├── run-ios-device-verification.sh # Physical iPhone sign/install/launch diagnostics
│   └── verify-ios-qa-gallery.sh  # Verify or refresh checked-in iPhone QA reference snapshots
├── .github/workflows/ci.yml      # macOS package checks + iOS QA verification on GitHub Actions
├── docs/qa-baselines/ios/        # Checked-in deterministic iPhone QA reference screenshots + environment contract
├── project.yml                   # xcodegen spec for iOS app/keyboard/test targets
├── VoiceInputCore/               # Cross-platform core models/settings/state
├── VoiceInputCoreTests/          # Core unit tests
├── VoiceInputiOS/                # iOS host app (onboarding/settings/quick notes)
├── VoiceInputiOSQA/              # Debug-only iOS QA gallery app target
├── VoiceInputKeyboard/           # iOS custom keyboard extension
├── VoiceInputMobileShared/       # Shared iOS runtime services (audio/transcription)
├── VoiceInputMobileTests/        # iOS test target (simulator)
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
