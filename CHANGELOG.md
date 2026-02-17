# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
