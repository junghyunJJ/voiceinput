import Foundation
import VoiceInputCore

@MainActor
final class KeyboardDictationViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var latestTranscription = ""
    @Published private(set) var hasTextBeforeCursor = false
    @Published var selectedLanguageName = DictationLanguage.auto.displayName
    @Published var autoInsertText = true
    @Published var quickActionTitle = TranscriptionOutputPreset.verbatim.quickActionTitle
    @Published var workflowSummary = "Quick: apply the selected preset to text before the cursor. Pro: Open App records in the iPhone app. Paste Last inserts saved app text."

    private let settingsStore: AppGroupSettingsStore?
    private let sharedDefaults: UserDefaults?

    private var selectedLanguage: DictationLanguage = .auto
    private var outputPreset: TranscriptionOutputPreset = .verbatim

    let primaryActionTitle = "Open App for Pro Dictation"
    let helperStatusTitle = "Helper Only"
    let helperStatusSymbolName = "arrow.up.right.square.fill"

    var hasSavedResult: Bool {
        !latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldRecommendPasteLast: Bool {
        hasSavedResult
    }

    var shouldRecommendProDictation: Bool {
        !hasSavedResult
    }

    var quickReadinessTitle: String {
        hasTextBeforeCursor ? "Text before cursor detected" : "Quick needs text before cursor"
    }

    var quickReadinessDetail: String {
        hasTextBeforeCursor
            ? "Quick only transforms existing text before the cursor."
            : "Type or dictate first, then use Quick on text before the cursor."
    }

    init(sharedDefaults: UserDefaults? = UserDefaults(suiteName: SharedContainerKeys.appGroupIdentifier),
         settingsStore: AppGroupSettingsStore? = nil,
         skipAppGroupSetup: Bool = false) {
        self.sharedDefaults = sharedDefaults
        self.latestTranscription = sharedDefaults?.string(forKey: SharedContainerKeys.lastTranscriptionKey) ?? ""

        if skipAppGroupSetup {
            self.settingsStore = settingsStore
            if settingsStore != nil {
                reloadSettings()
            }
            return
        }

        if let settingsStore {
            self.settingsStore = settingsStore
            reloadSettings()
            return
        }

        do {
            self.settingsStore = try AppGroupSettingsStore(
                appGroupIdentifier: SharedContainerKeys.appGroupIdentifier,
                validationPolicy: .requireAppGroup
            )
            reloadSettings()
        } catch {
            self.settingsStore = nil
            self.errorMessage = "Keyboard App Group setup is missing. Open the VoiceInput app and verify Signing & Capabilities."
        }
    }

    func reloadSettings() {
        guard let settings = settingsStore?.load() else {
            return
        }

        selectedLanguage = settings.selectedLanguage
        selectedLanguageName = selectedLanguage.displayName
        autoInsertText = settings.autoInsertText
        outputPreset = settings.outputPreset
        quickActionTitle = outputPreset.quickActionTitle
        workflowSummary = "Quick: \(outputPreset.displayName) applies to text before the cursor. Pro: Open App records in the iPhone app. Paste Last inserts saved app text."
    }

    func refresh(using helper: KeyboardTextDocumentHelperBridge) {
        reloadSettings()
        refreshLatestTranscription()
        refreshKeyboardContext(using: helper)
    }

    func openAppForProDictation(using helper: KeyboardTextDocumentHelperBridge, hasFullAccess: Bool) {
        recordingState = .idle
        errorMessage = nil
        infoMessage = hasFullAccess
            ? workflowSummary
            : "Enable Full Access to open the app from the keyboard and paste saved text. \(workflowSummary)"
        helper.openVoiceInputApp()
    }

    func reportHostAppLaunchFailure(hasFullAccess: Bool) {
        errorMessage = hasFullAccess
            ? "Could not open the VoiceInput app from the keyboard. Open the app once and try again."
            : "Enable Full Access to open the VoiceInput app from the keyboard."
    }

    func refreshKeyboardContext(using helper: KeyboardTextDocumentHelperBridge) {
        hasTextBeforeCursor = helper.hasTextBeforeCursor()
    }

    func polishCurrentDraft(using helper: KeyboardTextDocumentHelperBridge) {
        errorMessage = nil
        refreshKeyboardContext(using: helper)
        let processor = makePostTranscriptionProcessor()
        var didChange = false

        let didHandle = helper.transformCurrentDocumentText { currentText in
            let processedText = processor.process(currentText).processedText
            didChange = processedText != currentText
            return processedText
        }

        guard didHandle else {
            errorMessage = "Nothing before the cursor to transform yet. Dictate or type first, then tap \(quickActionTitle)."
            return
        }

        infoMessage = didChange
            ? "Quick mode applied \(outputPreset.displayName.lowercased()) to text before the cursor."
            : "Quick mode found no changes before the cursor."
    }

    func insertLastDictation(using helper: KeyboardTextDocumentHelperBridge) {
        refreshLatestTranscription()
        refreshKeyboardContext(using: helper)
        let text = sharedDefaults?
            .string(forKey: SharedContainerKeys.lastTranscriptionKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            errorMessage = "No saved transcription yet. Use Open App for Pro Dictation first, then tap Paste Last."
            return
        }

        errorMessage = nil
        helper.insertText(text)
        infoMessage = "Inserted the latest transcription from the iPhone app."
    }

    private func refreshLatestTranscription() {
        let current = sharedDefaults?.string(forKey: SharedContainerKeys.lastTranscriptionKey) ?? ""
        if current != latestTranscription {
            latestTranscription = current
        }
    }

    private func makePostTranscriptionProcessor() -> PostTranscriptionProcessor {
        let configuration = settingsStore?.load().postTranscriptionProcessingConfiguration ?? .noOp
        return PostTranscriptionProcessor(configuration: configuration)
    }
}
