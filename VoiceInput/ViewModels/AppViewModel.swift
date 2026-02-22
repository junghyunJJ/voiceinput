import AppKit
import Foundation
import ServiceManagement
import SwiftUI

private func trace(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/voiceinput-trace.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

private func log(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let logURL = URL(fileURLWithPath: "/tmp/voiceinput-debug.log")
    if let data = msg.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
    NSLog("%@", message)
}

/// Main coordinator for the Voice Input app.
/// Manages recording lifecycle, transcription, and text insertion.
@MainActor
@Observable
final class AppViewModel {
    // MARK: - State

    var recordingState: RecordingState = .idle
    var lastTranscription: String = ""
    var errorMessage: String?
    var showError = false

    // MARK: - Services

    var settings = AppSettings.shared
    let permissions = PermissionsManager()
    let modelManager = ModelManager()
    let hotkeyManager = HotkeyManager()

    private let audioService = AudioService()
    private let transcriptionEngine = WhisperKitEngine()
    private let textInsertionManager = TextInsertionManager()
    private var isModelLoaded = false
    private var overlayPanel: OverlayPanel?
    private var isProcessing = false  // Guard against duplicate hotkey triggers
    private var consecutiveNoAudioFailures = 0

    // MARK: - Init

    init() {
        setupHotkey()
        // Pre-load model on app launch (not lazily on menu open)
        Task { await self.setup() }
        // Prompt for accessibility if not already granted
        if !permissions.accessibilityGranted {
            permissions.requestAccessibilityPermission()
        }
    }

    // MARK: - Setup

    func setup() async {
        // Load the selected model on launch
        log("[VoiceInput] Setup: loading model '\(settings.selectedModel)'...")
        do {
            try await transcriptionEngine.loadModel(variant: settings.selectedModel)
            isModelLoaded = true
            log("[VoiceInput] Setup: model loaded successfully")
        } catch {
            log("[VoiceInput] Setup: model load failed: \(error)")
            self.errorMessage = "Failed to load model: \(error.localizedDescription)"
            self.showError = true
        }
    }

    private func setupHotkey() {
        hotkeyManager.onRecordingStarted = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.startRecording()
            }
        }

        hotkeyManager.onRecordingStopped = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.stopRecording()
            }
        }

        hotkeyManager.onCopyRequested = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.copyLastTranscription()
            }
        }

        hotkeyManager.register(
            mode: settings.hotkeyMode,
            copyShortcut: settings.copyActionShortcut
        )
    }

    // MARK: - Recording Control

    func toggleRecording() async {
        if recordingState.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard recordingState.isIdle, !isProcessing else {
            log("[VoiceInput] startRecording: not idle or already processing, state=\(recordingState)")
            return
        }
        isProcessing = true

        // Check permissions
        log("[VoiceInput] Checking mic permission: \(permissions.microphoneGranted)")
        if !permissions.microphoneGranted {
            let granted = await permissions.requestMicrophonePermission()
            log("[VoiceInput] Mic permission result: \(granted)")
            if !granted {
                isProcessing = false
                hotkeyManager.resetState()
                setError("Microphone permission is required.")
                return
            }
        }

        // Check model
        log("[VoiceInput] Model loaded: \(isModelLoaded), selected: \(settings.selectedModel)")
        if !isModelLoaded {
            do {
                log("[VoiceInput] Loading model \(settings.selectedModel)...")
                try await transcriptionEngine.loadModel(variant: settings.selectedModel)
                isModelLoaded = true
                log("[VoiceInput] Model loaded successfully")
            } catch {
                log("[VoiceInput] Model load error: \(error)")
                isProcessing = false
                hotkeyManager.resetState()
                setError("Failed to load model: \(error.localizedDescription)")
                return
            }
        }

        // Start audio capture
        do {
            log("[VoiceInput] Starting audio capture...")
            try await audioService.startCapture()
            recordingState = .recording(startTime: Date())
            log("[VoiceInput] Recording started!")
            // Do not play start sound here: output route changes can interrupt input taps.
            if settings.showOverlay { showOverlayPanel() }
        } catch {
            log("[VoiceInput] Audio capture error: \(error)")
            isProcessing = false
            hotkeyManager.resetState()
            setError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard recordingState.isRecording else {
            log("[VoiceInput] stopRecording: not recording, state=\(recordingState)")
            return
        }

        // Stop capture and get audio samples
        log("[VoiceInput] Stopping audio capture...")
        let captureResult = await audioService.stopCapture()
        let audioSamples = captureResult.samples
        let sourceRateText = captureResult.sourceSampleRate.map { String(format: "%.1f", $0) } ?? "nil"
        log("[VoiceInput] Capture result: reason=\(captureResult.stopReason.rawValue), tap=\(captureResult.didReceiveTap), rawBuffers=\(captureResult.rawBufferCount), frames=\(captureResult.totalFrames), sourceRate=\(sourceRateText)")
        log("[VoiceInput] Got \(audioSamples.count) samples (\(String(format: "%.1f", Double(audioSamples.count) / 16000))s)")
        // Audio cues are disabled to avoid Bluetooth/output route churn that can drop mic capture.

        guard !audioSamples.isEmpty else {
            await handleNoAudioCapture(captureResult)
            return
        }
        consecutiveNoAudioFailures = 0

        // Transcribe
        recordingState = .transcribing
        log("[VoiceInput] Starting transcription...")

        do {
            let language: String? = settings.selectedLanguage == .auto
                ? nil
                : settings.selectedLanguage.rawValue

            let result = try await transcriptionEngine.transcribe(
                audioSamples: audioSamples,
                language: language
            )
            let transcribedText = result.text
            let transcribedLang = result.language
            let transcribedDuration = result.duration
            log("[VoiceInput] Transcription result: '\(transcribedText)' (lang: \(transcribedLang), \(String(format: "%.2f", transcribedDuration))s)")

            guard !transcribedText.isEmpty else {
                log("[VoiceInput] Empty transcription, returning to idle")
                finishRecordingCycle()
                return
            }

            lastTranscription = transcribedText

            // Insert text at cursor
            if settings.autoInsertText {
                recordingState = .inserting(text: transcribedText)

                // Refresh accessibility check (may change after app launch or rebuild)
                permissions.refreshPermissions()
                log("[VoiceInput] Accessibility granted: \(permissions.accessibilityGranted)")
                log("[VoiceInput] Inserting text: '\(transcribedText.prefix(50))...'")

                // Pass accessibility status so insertion can choose the right method
                let insertResult = textInsertionManager.insert(transcribedText, accessibilityAvailable: permissions.accessibilityGranted)
                log("[VoiceInput] Insert result: success=\(insertResult.success), method=\(insertResult.method.rawValue)")

                if !insertResult.success {
                    copyToClipboardWithNotification(transcribedText)
                }
            } else {
                log("[VoiceInput] autoInsertText is OFF, skipping insertion")
            }

            finishRecordingCycle()
        } catch {
            finishRecordingCycle()
            setError("Transcription failed: \(error.localizedDescription)")
        }
    }

    private func handleNoAudioCapture(_ result: AudioCaptureResult) async {
        log("[VoiceInput] No audio samples, returning to idle")
        finishRecordingCycle()
        consecutiveNoAudioFailures += 1

        let reason = result.stopReason.rawValue
        log("[VoiceInput] No-audio failure count: \(consecutiveNoAudioFailures), reason=\(reason)")
        // Keep this non-blocking for UX; avoid modal error popups on intermittent capture misses.
    }

    // MARK: - Overlay Panel

    private func showOverlayPanel() {
        let panel = OverlayPanel()
        let hostingView = NSHostingView(rootView: RecordingOverlayView(viewModel: self))
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.overlayPanel = panel
    }

    private func hideOverlayPanel() {
        overlayPanel?.close()
        overlayPanel = nil
    }

    /// Finalize one recording cycle and return UI/hotkey state to ready mode.
    private func finishRecordingCycle() {
        recordingState = .idle
        isProcessing = false
        hideOverlayPanel()
        hotkeyManager.resetState()
    }

    // MARK: - Model Management

    func switchModel(to variant: String) async {
        isModelLoaded = false
        await transcriptionEngine.unloadModel()
        settings.selectedModel = variant

        do {
            try await transcriptionEngine.loadModel(variant: variant)
            isModelLoaded = true
        } catch {
            setError("Failed to load model '\(variant)': \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    func updateHotkeyMode(_ mode: HotkeyMode) {
        settings.hotkeyMode = mode
        hotkeyManager.register(mode: mode, copyShortcut: settings.copyActionShortcut)
    }

    func updateCopyActionShortcut(_ shortcut: CopyActionShortcut) {
        settings.copyActionShortcut = shortcut
        hotkeyManager.updateCopyShortcut(shortcut)
    }

    func copyLastTranscription() {
        guard !lastTranscription.isEmpty else { return }
        copyToClipboard(lastTranscription)
        log("[VoiceInput] Copied last transcription to clipboard")
    }

    func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            setError("Failed to update launch at login: \(error.localizedDescription)")
            settings.launchAtLogin.toggle() // Revert
        }
    }

    // MARK: - Clipboard Fallback

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyToClipboardWithNotification(_ text: String) {
        copyToClipboard(text)
        log("[VoiceInput] Copied to clipboard (Cmd+V to paste)")
    }

    // MARK: - Error Handling

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
        recordingState = .error(message: message)

        // Auto-clear error after 5 seconds
        Task {
            try? await Task.sleep(for: .seconds(5))
            if case .error = recordingState {
                recordingState = .idle
            }
            showError = false
        }
    }

    // MARK: - App Actions

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - System Sounds

extension NSSound {
    static let Tink = NSSound(named: "Tink")
    static let Pop = NSSound(named: "Pop")
}
