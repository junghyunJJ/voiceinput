import AVFoundation
import Foundation
import UIKit
import VoiceInputCore
import VoiceInputMobileShared

@MainActor
final class IOSDictationViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var transcribedText = ""
    @Published private(set) var savedKeyboardText = ""
    @Published var errorMessage: String?
    @Published var setupErrorMessage: String?
    @Published var selectedLanguage: DictationLanguage = .auto
    @Published var selectedModel = MobileConstants.Transcription.defaultModel
    @Published var autoInsertText = true
    @Published var keepQuickNoteHistory = true
    @Published var outputPreset: TranscriptionOutputPreset = .verbatim
    @Published var glossary: [TranscriptionGlossaryItem] = []
    @Published var corrections: [TranscriptionCorrectionRule] = []
    @Published var candidateCorrections: [TranscriptionCandidateCorrectionRule] = []
    @Published var suppressedCandidateSuggestions: [TranscriptionCandidateCorrection] = []
    @Published var quickNoteHistory: [String] = []
    @Published var showOpenSettingsShortcut = false
    @Published var infoMessage: String?

    let supportedLanguages: [DictationLanguage] = [.auto, .english, .korean, .japanese, .chinese]
    let modelVariants = MobileConstants.Transcription.modelVariants

    private let audioCapture = MobileAudioCaptureService()
    private let transcriber = MobileWhisperKitTranscriber()
    private let settingsStore: AppGroupSettingsStore?
    private let sharedDefaults: UserDefaults?
    private let copyToClipboard: (String) -> Void

    init(
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: MobileConstants.appGroupIdentifier),
        settingsStore: AppGroupSettingsStore? = nil,
        skipAppGroupSetup: Bool = false,
        copyToClipboard: @escaping (String) -> Void = { UIPasteboard.general.string = $0 }
    ) {
        self.sharedDefaults = sharedDefaults
        self.copyToClipboard = copyToClipboard

        if skipAppGroupSetup {
            self.settingsStore = settingsStore
            if let settings = settingsStore?.load() {
                apply(settings: settings)
            }
            loadQuickNoteHistory()
            loadSavedKeyboardResult()
            return
        }

        if let settingsStore {
            self.settingsStore = settingsStore
            apply(settings: settingsStore.load())
            loadQuickNoteHistory()
            loadSavedKeyboardResult()
            return
        }

        do {
            let resolvedStore = try AppGroupSettingsStore(
                appGroupIdentifier: MobileConstants.appGroupIdentifier,
                validationPolicy: .requireAppGroup
            )
            self.settingsStore = resolvedStore
            apply(settings: resolvedStore.load())
        } catch {
            self.settingsStore = nil
            self.setupErrorMessage = "App Group is not configured. Check Signing & Capabilities."
            self.showOpenSettingsShortcut = true
        }

        loadQuickNoteHistory()
        loadSavedKeyboardResult()
    }

    var hasSavedKeyboardResult: Bool {
        !savedKeyboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasUnsavedKeyboardEdits: Bool {
        transcribedText != savedKeyboardText
    }

    var canUpdatePasteLast: Bool {
        hasUnsavedKeyboardEdits
    }

    func toggleRecording() {
        Task {
            if recordingState.isRecording {
                await stopAndTranscribe()
            } else {
                await startRecording()
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "voiceinput" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let shouldAutoDictate = components?.queryItems?.contains(where: { item in
            item.name == "dictate" && item.value == "1"
        }) ?? false

        guard shouldAutoDictate else {
            return
        }

        infoMessage = "Started from keyboard Pro mode. Tap Stop & Transcribe, then return to keyboard and tap Paste Last."
        if !recordingState.isRecording {
            Task {
                await startRecording()
            }
        }
    }

    func persistSettings() {
        let sanitizedSettings = currentSharedSettings().sanitizedForPersistence
        settingsStore?.save(sanitizedSettings)

        if !keepQuickNoteHistory, !quickNoteHistory.isEmpty {
            clearQuickNoteHistory()
        }
    }

    private func startRecording() async {
        errorMessage = nil
        let granted = await requestMicrophonePermission()
        guard granted else {
            recordingState = .error(message: "Microphone permission denied")
            errorMessage = "Enable microphone access in Settings > Privacy & Security > Microphone."
            showOpenSettingsShortcut = true
            return
        }

        do {
            try await transcriber.loadModelIfNeeded(variant: selectedModel)
            try await audioCapture.startCapture()
            recordingState = .recording(startTime: Date())
            showOpenSettingsShortcut = false
        } catch {
            recordingState = .error(message: "Failed to start recording")
            errorMessage = userFacingErrorMessage(from: error)
        }
    }

    private func stopAndTranscribe() async {
        recordingState = .transcribing

        let capture = await audioCapture.stopCapture()
        guard !capture.samples.isEmpty else {
            recordingState = .error(message: "No audio captured")
            errorMessage = "No audio samples were recorded."
            return
        }

        do {
            let result = try await transcriber.transcribe(
                samples: capture.samples,
                language: selectedLanguage.whisperCode
            )

            let processed = makePostTranscriptionProcessor().process(result.text)
            let processedText = processed.processedText
            setDraftAndCommitKeyboardResult(processedText)
            appendQuickNoteIfNeeded(processedText)
            recordingState = .idle
        } catch {
            recordingState = .error(message: "Transcription failed")
            errorMessage = userFacingErrorMessage(from: error)
        }
    }

    func refreshSuppressedCandidateSuggestions() {
        let current = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            suppressedCandidateSuggestions = []
            return
        }

        suppressedCandidateSuggestions = makePostTranscriptionProcessor()
            .process(transcribedText)
            .suppressedCandidates
    }

    @discardableResult
    func applySuppressedCandidateSuggestion(at index: Int) -> Bool {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return false
        }

        let candidate = suppressedCandidateSuggestions[index]
        guard let updated = candidate.applying(to: transcribedText) else {
            return false
        }

        setDraftAndCommitKeyboardResult(updated)
        return true
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
        return true
    }

    @discardableResult
    func copySavedKeyboardResult() -> Bool {
        guard hasSavedKeyboardResult else {
            return false
        }

        copyToClipboard(savedKeyboardText)
        infoMessage = "Copied the saved keyboard result."
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

        let candidate = suppressedCandidateSuggestions[index]
        let updatedDraft = candidate.applying(to: transcribedText)
        let updatedRules = candidateCorrections.upsertingPromotedSuggestion(
            candidate
        )
        let existingRules = candidateCorrections
        candidateCorrections = updatedRules
        persistSettings()

        if let updatedDraft {
            setDraftAndCommitKeyboardResult(updatedDraft)
        }
        else {
            refreshSuppressedCandidateSuggestions()
        }

        let didChangeRule = updatedRules != existingRules
        let didApplyDraft = updatedDraft != nil

        if didChangeRule && didApplyDraft {
            infoMessage = "Saved as an always-on local correction rule and updated this draft."
            return true
        }

        if didChangeRule {
            infoMessage = "Saved as an always-on local correction rule."
            return true
        }

        if didApplyDraft {
            infoMessage = "This correction rule was already saved, so this draft was updated."
            return true
        }

        infoMessage = "This correction rule is already saved."
        return false
    }

    @discardableResult
    func updatePasteLastFromCurrentDraft() -> Bool {
        guard hasUnsavedKeyboardEdits else {
            infoMessage = "Paste Last is already up to date."
            return false
        }

        writeKeyboardSavedResult(transcribedText)
        let trimmedDraft = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        infoMessage = trimmedDraft.isEmpty
            ? "Cleared the saved keyboard result."
            : "Updated Paste Last with the current draft."
        return true
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func correctedSuppressedCandidateSuggestion(at index: Int) -> String? {
        guard suppressedCandidateSuggestions.indices.contains(index) else {
            return nil
        }

        let candidate = suppressedCandidateSuggestions[index]
        return candidate.applying(to: transcribedText)
    }

    func clearQuickNoteHistory() {
        quickNoteHistory = []
        sharedDefaults?.removeObject(forKey: MobileConstants.quickNoteHistoryKey)
    }

    func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    func addGlossaryItem() {
        glossary.append(
            TranscriptionGlossaryItem(
                phrase: "",
                replacement: "",
                aliases: []
            )
        )
        persistSettings()
    }

    func addCorrectionRule() {
        corrections.append(
            TranscriptionCorrectionRule(
                source: "",
                replacement: ""
            )
        )
        persistSettings()
    }

    func addCandidateCorrectionRule() {
        candidateCorrections.append(
            TranscriptionCandidateCorrectionRule(
                source: "",
                aliases: [],
                replacement: "",
                confidence: 0.9,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        )
        persistSettings()
    }

    func removeGlossaryItem(at index: Int) {
        guard glossary.indices.contains(index) else {
            return
        }

        glossary.remove(at: index)
        persistSettings()
    }

    func removeCorrectionRule(at index: Int) {
        guard corrections.indices.contains(index) else {
            return
        }

        corrections.remove(at: index)
        persistSettings()
    }

    func removeCandidateCorrectionRule(at index: Int) {
        guard candidateCorrections.indices.contains(index) else {
            return
        }

        candidateCorrections.remove(at: index)
        persistSettings()
    }

    private func loadQuickNoteHistory() {
        guard let data = sharedDefaults?.data(forKey: MobileConstants.quickNoteHistoryKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            quickNoteHistory = []
            return
        }

        quickNoteHistory = decoded
    }

    private func saveQuickNoteHistory() {
        guard let data = try? JSONEncoder().encode(quickNoteHistory) else {
            return
        }

        sharedDefaults?.set(data, forKey: MobileConstants.quickNoteHistoryKey)
    }

    private func appendQuickNoteIfNeeded(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keepQuickNoteHistory, !cleaned.isEmpty else {
            return
        }

        let timestamp = Date.now.formatted(date: .numeric, time: .shortened)
        quickNoteHistory.insert("[\(timestamp)] \(cleaned)", at: 0)
        if quickNoteHistory.count > 30 {
            quickNoteHistory.removeLast(quickNoteHistory.count - 30)
        }
        saveQuickNoteHistory()
    }

    private func loadSavedKeyboardResult() {
        let savedText = sharedDefaults?.string(forKey: MobileConstants.lastTranscriptionKey) ?? ""
        savedKeyboardText = savedText
        if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcribedText = savedText
        }
    }

    private func setDraftAndCommitKeyboardResult(_ text: String) {
        transcribedText = text
        writeKeyboardSavedResult(text)
        refreshSuppressedCandidateSuggestions()
    }

    private func writeKeyboardSavedResult(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            sharedDefaults?.removeObject(forKey: MobileConstants.lastTranscriptionKey)
            savedKeyboardText = ""
            return
        }

        sharedDefaults?.set(text, forKey: MobileConstants.lastTranscriptionKey)
        savedKeyboardText = text
    }

    private func userFacingErrorMessage(from error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }

        let fallback = error.localizedDescription
        let lower = fallback.lowercased()
        if lower.contains("/private/var/mobile/containers/") ||
            lower.contains(".mlmodelc") ||
            lower.contains("weight.bin")
        {
            return "Model files could not be loaded. VoiceInput will retry model download automatically. Keep network stable and try Start Dictation again."
        }

        return fallback
    }

    private func currentSharedSettings() -> SharedSettings {
        var settings = settingsStore?.load() ?? .default
        settings.selectedLanguage = selectedLanguage
        settings.selectedModel = selectedModel
        settings.autoInsertText = autoInsertText
        settings.keepQuickNoteHistory = keepQuickNoteHistory
        settings.outputPreset = outputPreset
        settings.glossary = glossary.normalizedForPersistence
        settings.corrections = corrections.normalizedForPersistence
        settings.candidateCorrections = candidateCorrections.normalizedForEvaluation
        return settings
    }

    private func makePostTranscriptionProcessor() -> PostTranscriptionProcessor {
        PostTranscriptionProcessor(
            configuration: currentSharedSettings().postTranscriptionProcessingConfiguration
        )
    }

    private func apply(settings: SharedSettings) {
        selectedLanguage = settings.selectedLanguage
        selectedModel = settings.selectedModel.isEmpty
            ? MobileConstants.Transcription.defaultModel
            : settings.selectedModel
        autoInsertText = settings.autoInsertText
        keepQuickNoteHistory = settings.keepQuickNoteHistory
        outputPreset = settings.outputPreset
        glossary = settings.glossary
        corrections = settings.corrections
        candidateCorrections = settings.candidateCorrections
    }
}
