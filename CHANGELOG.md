# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.2] - 2026-10-15

### Fixed

- Automatically paste completed dictation into native apps, browser editors, and terminal input using standard paste events.
- Preserve the previous clipboard without overwriting content copied while a paste is completing, and retain dictation for manual paste if automatic paste is unavailable.
- Install the freshly built SwiftPM executable instead of a stale binary, including when the development script is launched from another directory.
- Improve empty-transcription handling and decoder diagnostics.
- Load complete cached speech models without a network lookup, and reject incomplete model caches.

### Changed

- Upgrade WhisperKit to 1.0.0 and use the supported Large v3 Turbo model variant, including migration of legacy selections.

## [0.5.1] - 2026-05-22

### Changed

- Stabilized recording startup by adding guarded startup retries and best-effort capture fallback in `AudioService`.
- Added richer no-audio diagnostics (`engineConfigurationChanged`, `engineStoppedBeforeFirstTap`) to distinguish tap/engine startup failures.
- Disabled app audio cues during recording flows to reduce Bluetooth/output route churn that could interrupt microphone capture.

### Added

- Added stop-reason classifier coverage in `VoiceInputTests/AudioCaptureStopReasonTests.swift`.

## [1.0.0] - 2025-02-16

### Added

- On-device speech-to-text using WhisperKit (Core ML).
- Menu bar interface with recording controls and settings.
- Global hotkey support for hands-free recording.
- Multi-language transcription (English, Korean, Japanese, Chinese, Spanish, French, German).
- Smart text insertion via Accessibility API, keyboard simulation, and clipboard fallback.
- Model manager for downloading and switching between Whisper models (tiny, base, small, large-v3).
- Recording overlay indicator.
- Onboarding flow for first-launch permission setup.
- Development build script (`build-dev.sh`).
- Release build script with code signing, notarization, and DMG packaging (`build-release.sh`).
