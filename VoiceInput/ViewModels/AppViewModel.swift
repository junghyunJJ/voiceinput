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

        hotkeyManager.register(mode: settings.hotkeyMode)
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
            if settings.playSound { NSSound.Tink?.play() }
            if settings.showOverlay { showOverlayPanel() }
        } catch {
            log("[VoiceInput] Audio capture error: \(error)")
            isProcessing = false
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
        let audioSamples = await audioService.stopCapture()
        log("[VoiceInput] Got \(audioSamples.count) samples (\(String(format: "%.1f", Double(audioSamples.count) / 16000))s)")
        if settings.playSound { NSSound.Pop?.play() }

        guard !audioSamples.isEmpty else {
            log("[VoiceInput] No audio samples, returning to idle")
            recordingState = .idle
            return
        }

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
                recordingState = .idle
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

            recordingState = .idle
            isProcessing = false
            hideOverlayPanel()
        } catch {
            isProcessing = false
            hideOverlayPanel()
            setError("Transcription failed: \(error.localizedDescription)")
        }
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
        hotkeyManager.register(mode: mode)
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

    private func copyToClipboardWithNotification(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log("[VoiceInput] Copied to clipboard (Cmd+V to paste)")
        if settings.playSound { NSSound.Pop?.play() }
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
