import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import VoiceInputCore

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
struct AppViewModelDependencies {
    var isMicrophoneGranted: () -> Bool
    var requestMicrophonePermission: () async -> Bool
    var isAccessibilityGranted: () -> Bool
    var refreshPermissions: () -> Void
    var requestAccessibilityPermission: () -> Void
    var loadModel: (String) async throws -> Void
    var unloadModel: () async -> Void
    var startCapture: () async throws -> Void
    var stopCapture: () async -> AudioCaptureResult
    var transcribe: ([Float], String?) async throws -> TranscriptionResult
    var processTranscription: (String) -> PostTranscriptionProcessingResult
    var insertText: (String, Bool) -> TextInsertionManager.InsertionResult
    var repairInsertedText: (String, TextInsertionManager.RepairContext, Bool) -> TextInsertionManager.InsertionResult
    var resetHotkeyState: () -> Void
    var registerHotkeys: (HotkeyMode, CopyActionShortcut) -> Void
    var updateCopyShortcut: (CopyActionShortcut) -> Void
    var copyToClipboard: (String) -> Void
}

@MainActor
@Observable
final class AppViewModel {
    private struct RecentInsertionState {
        let insertedText: String
        let method: TextInsertionManager.InsertionMethod
        let repairContext: TextInsertionManager.RepairContext?
    }

    // MARK: - State

    var recordingState: RecordingState = .idle
    var lastTranscription: String = ""
    var suppressedCandidateSuggestions: [TranscriptionCandidateCorrection] = []
    var errorMessage: String?
    var showError = false
    var canRepairSuppressedCandidateSuggestions: Bool {
        guard let recentInsertionState else {
            return false
        }

        return recentInsertionState.method == .accessibility &&
            recentInsertionState.repairContext != nil &&
            recentInsertionState.insertedText == lastTranscription
    }
    var suppressedCandidateRepairUnavailableReason: String? {
        guard !suppressedCandidateSuggestions.isEmpty,
              !canRepairSuppressedCandidateSuggestions else {
            return nil
        }

        guard let recentInsertionState else {
            return "In-place repair is only available for the most recent Accessibility insertion."
        }

        if recentInsertionState.method != .accessibility {
            return "This text was inserted via keyboard or clipboard fallback, so it can't be repaired in place."
        }

        if recentInsertionState.repairContext == nil {
            return "This insertion did not capture a repairable Accessibility context."
        }

        return "The inserted app text changed, so in-place repair is unavailable."
    }

    // MARK: - Services

    var settings: AppSettings
    let permissions: PermissionsManager
    let modelManager: ModelManager
    let hotkeyManager: HotkeyManager

    private let dependencies: AppViewModelDependencies
    private var isModelLoaded = false
    private var overlayPanel: OverlayPanel?
    private var isProcessing = false  // Guard against duplicate hotkey triggers
    private let noAudioFailureErrorThreshold = 3
    private var consecutiveNoAudioFailures = 0
    private var recentInsertionState: RecentInsertionState?

    // MARK: - Init

    convenience init() {
        self.init(
            settings: .shared,
            permissions: PermissionsManager(),
            modelManager: ModelManager(),
            hotkeyManager: HotkeyManager(),
            audioService: AudioService(),
            transcriptionEngine: WhisperKitEngine(),
            textInsertionManager: TextInsertionManager(),
            postTranscriptionProcessor: PostTranscriptionProcessor()
        )
    }

    init(
        settings: AppSettings,
        permissions: PermissionsManager,
        modelManager: ModelManager,
        hotkeyManager: HotkeyManager,
        audioService: AudioService,
        transcriptionEngine: any TranscriptionEngine,
        textInsertionManager: TextInsertionManager,
        postTranscriptionProcessor: PostTranscriptionProcessor,
        dependencies: AppViewModelDependencies? = nil,
        autoSetup: Bool = true,
        promptForAccessibilityIfNeeded: Bool = true
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager
        self.dependencies = dependencies ?? AppViewModelDependencies(
            isMicrophoneGranted: { permissions.microphoneGranted },
            requestMicrophonePermission: { await permissions.requestMicrophonePermission() },
            isAccessibilityGranted: { permissions.accessibilityGranted },
            refreshPermissions: { permissions.refreshPermissions() },
            requestAccessibilityPermission: { permissions.requestAccessibilityPermission() },
            loadModel: { variant in
                try await transcriptionEngine.loadModel(variant: variant)
            },
            unloadModel: {
                await transcriptionEngine.unloadModel()
            },
            startCapture: {
                try await audioService.startCapture()
            },
            stopCapture: {
                await audioService.stopCapture()
            },
            transcribe: { audioSamples, language in
                try await transcriptionEngine.transcribe(audioSamples: audioSamples, language: language)
            },
            processTranscription: { [settings] text in
                let effectiveProcessor = PostTranscriptionProcessor(
                    configuration: settings.postTranscriptionProcessingConfiguration
                )
                return effectiveProcessor.process(text)
            },
            insertText: { text, accessibilityAvailable in
                textInsertionManager.insert(text, accessibilityAvailable: accessibilityAvailable)
            },
            repairInsertedText: { text, context, accessibilityAvailable in
                textInsertionManager.repairRecentlyInsertedText(
                    text,
                    using: context,
                    accessibilityAvailable: accessibilityAvailable
                )
            },
            resetHotkeyState: { hotkeyManager.resetState() },
            registerHotkeys: { mode, copyShortcut in
                hotkeyManager.register(mode: mode, copyShortcut: copyShortcut)
            },
            updateCopyShortcut: { shortcut in
                hotkeyManager.updateCopyShortcut(shortcut)
            },
            copyToClipboard: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        )

        setupHotkey()
        if autoSetup {
            // Pre-load model on app launch (not lazily on menu open)
            Task { await self.setup() }
        }
        // Prompt for accessibility if not already granted
        if promptForAccessibilityIfNeeded && !permissions.accessibilityGranted {
            self.dependencies.requestAccessibilityPermission()
        }
    }

    // MARK: - Setup

    func setup() async {
        // Load the selected model on launch
        log("[VoiceInput] Setup: loading model '\(settings.selectedModel)'...")
        do {
            try await dependencies.loadModel(settings.selectedModel)
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

        dependencies.registerHotkeys(settings.hotkeyMode, settings.copyActionShortcut)
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
        log("[VoiceInput] Checking mic permission: \(dependencies.isMicrophoneGranted())")
        if !dependencies.isMicrophoneGranted() {
            let granted = await dependencies.requestMicrophonePermission()
            log("[VoiceInput] Mic permission result: \(granted)")
            if !granted {
                isProcessing = false
                dependencies.resetHotkeyState()
                setError("Microphone permission is required.")
                return
            }
        }

        // Check model
        log("[VoiceInput] Model loaded: \(isModelLoaded), selected: \(settings.selectedModel)")
        if !isModelLoaded {
            do {
                log("[VoiceInput] Loading model \(settings.selectedModel)...")
                try await dependencies.loadModel(settings.selectedModel)
                isModelLoaded = true
                log("[VoiceInput] Model loaded successfully")
            } catch {
                log("[VoiceInput] Model load error: \(error)")
                isProcessing = false
                dependencies.resetHotkeyState()
                setError("Failed to load model: \(error.localizedDescription)")
                return
            }
        }

        // Start audio capture
        do {
            log("[VoiceInput] Starting audio capture...")
            try await dependencies.startCapture()
            recordingState = .recording(startTime: Date())
            log("[VoiceInput] Recording started!")
            // Do not play start sound here: output route changes can interrupt input taps.
            if settings.showOverlay { showOverlayPanel() }
        } catch {
            log("[VoiceInput] Audio capture error: \(error)")
            isProcessing = false
            dependencies.resetHotkeyState()
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
        let captureResult = await dependencies.stopCapture()
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

            let result = try await dependencies.transcribe(audioSamples, language)
            let processedResult = dependencies.processTranscription(result.text)
            let transcribedText = processedResult.processedText
            let transcribedLang = result.language
            let transcribedDuration = result.duration
            log("[VoiceInput] Transcription result: '\(transcribedText)' (lang: \(transcribedLang), \(String(format: "%.2f", transcribedDuration))s)")

            guard !transcribedText.isEmpty else {
                log("[VoiceInput] Empty transcription, returning to idle")
                finishRecordingCycle()
                return
            }

            lastTranscription = transcribedText
            suppressedCandidateSuggestions = refreshedSuppressedCandidates(for: transcribedText)
            recentInsertionState = nil

            // Insert text at cursor
            if settings.autoInsertText {
                recordingState = .inserting(text: transcribedText)

                // Refresh accessibility check (may change after app launch or rebuild)
                dependencies.refreshPermissions()
                let accessibilityGranted = dependencies.isAccessibilityGranted()
                log("[VoiceInput] Accessibility granted: \(accessibilityGranted)")
                log("[VoiceInput] Inserting text: '\(transcribedText.prefix(50))...'")

                // Pass accessibility status so insertion can choose the right method
                let insertResult = dependencies.insertText(transcribedText, accessibilityGranted)
                log("[VoiceInput] Insert result: success=\(insertResult.success), method=\(insertResult.method.rawValue)")

                if insertResult.success {
                    recentInsertionState = RecentInsertionState(
                        insertedText: transcribedText,
                        method: insertResult.method,
                        repairContext: insertResult.repairContext
                    )
                } else {
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
        guard consecutiveNoAudioFailures >= noAudioFailureErrorThreshold else {
            // Keep this non-blocking for UX; avoid modal error popups on intermittent capture misses.
            return
        }

        setError(noAudioCaptureMessage(for: result.stopReason))
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
        dependencies.resetHotkeyState()
    }

    // MARK: - Model Management

    func switchModel(to variant: String) async {
        isModelLoaded = false
        await dependencies.unloadModel()
        settings.selectedModel = variant

        do {
            try await dependencies.loadModel(variant)
            isModelLoaded = true
        } catch {
            setError("Failed to load model '\(variant)': \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    func updateHotkeyMode(_ mode: HotkeyMode) {
        settings.hotkeyMode = mode
        dependencies.registerHotkeys(mode, settings.copyActionShortcut)
    }

    func updateCopyActionShortcut(_ shortcut: CopyActionShortcut) {
        settings.copyActionShortcut = shortcut
        dependencies.updateCopyShortcut(shortcut)
    }

    func copyLastTranscription() {
        guard !lastTranscription.isEmpty else { return }
        copyToClipboard(lastTranscription)
        log("[VoiceInput] Copied last transcription to clipboard")
    }

    func canCopySuppressedCandidateSuggestion(at index: Int) -> Bool {
        correctedSuppressedCandidateSuggestion(at: index) != nil
    }

    @discardableResult
    func copySuppressedCandidateSuggestion(at index: Int) -> Bool {
        guard let correctedText = correctedSuppressedCandidateSuggestion(at: index) else {
            return false
        }

        copyToClipboard(correctedText)
        log("[VoiceInput] Copied corrected suggestion to clipboard")
        return true
    }

    func canSaveSuppressedCandidateSuggestionAsRule(at index: Int) -> Bool {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return false
        }

        return suppressedCandidateSuggestions[index].promotedAlwaysApplyRule != nil
    }

    @discardableResult
    func saveSuppressedCandidateSuggestionAsRule(at index: Int) -> Bool {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return false
        }

        let existingRules = settings.transcriptionCandidateCorrections
        let updatedRules = existingRules.upsertingPromotedSuggestion(
            suppressedCandidateSuggestions[index]
        )
        guard updatedRules != existingRules else {
            log("[VoiceInput] Suppressed suggestion rule already saved")
            return false
        }

        settings.transcriptionCandidateCorrections = updatedRules
        log("[VoiceInput] Saved suppressed suggestion as always-on correction rule")
        return true
    }

    @discardableResult
    func applySuppressedCandidateSuggestion(at index: Int) -> Bool {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return false
        }

        let candidate = suppressedCandidateSuggestions[index]
        guard let updated = candidate.applying(to: lastTranscription) else {
            return false
        }

        guard let currentInsertionState = recentInsertionState,
              currentInsertionState.insertedText == lastTranscription,
              let repairContext = currentInsertionState.repairContext,
              currentInsertionState.method == .accessibility else {
            return false
        }

        dependencies.refreshPermissions()
        let accessibilityGranted = dependencies.isAccessibilityGranted()
        let repairResult = dependencies.repairInsertedText(
            updated,
            repairContext,
            accessibilityGranted
        )
        guard repairResult.success else {
            return false
        }

        recentInsertionState = RecentInsertionState(
            insertedText: updated,
            method: repairResult.method,
            repairContext: repairResult.repairContext
        )

        lastTranscription = updated
        suppressedCandidateSuggestions = refreshedSuppressedCandidates(for: updated)
        return true
    }

    private func refreshedSuppressedCandidates(for visibleText: String) -> [TranscriptionCandidateCorrection] {
        dependencies.processTranscription(visibleText).suppressedCandidates
    }

    private func correctedSuppressedCandidateSuggestion(at index: Int) -> String? {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return nil
        }

        let candidate = suppressedCandidateSuggestions[index]
        return candidate.applying(to: lastTranscription)
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
        dependencies.copyToClipboard(text)
    }

    private func copyToClipboardWithNotification(_ text: String) {
        copyToClipboard(text)
        log("[VoiceInput] Copied to clipboard (Cmd+V to paste)")
    }

    private func noAudioCaptureMessage(for reason: AudioCaptureStopReason) -> String {
        switch reason {
        case .engineConfigurationChanged, .engineStoppedBeforeFirstTap:
            return "Microphone capture stopped before any audio reached Voice Input. Check System Settings > Sound > Input, switch to the microphone you want to use, then retry."
        case .notCapturing, .noRawBuffersCaptured, .zeroFramesCaptured, .conversionFailed, .ok:
            return "Voice Input did not receive usable microphone audio. Check System Settings > Sound > Input and confirm your microphone is available, then retry."
        }
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
