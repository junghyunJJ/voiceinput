import Foundation
import Testing
import VoiceInputCore
@testable import VoiceInputKeyboard

@Suite("Keyboard Helper-Only Boundary Tests")
struct KeyboardHelperOnlyBoundaryTests {

    @MainActor
    @Test func keyboardViewControllerIsTheConcreteTextDocumentHelper() {
        let controller = KeyboardViewController()
        let helper: any KeyboardTextDocumentHelping = controller

        #expect((helper as AnyObject) === controller)
    }

    @MainActor
    @Test func primaryActionOpensHostAppAndExplainsQuickProWorkflow() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helper = KeyboardHelperSpy()
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.openAppForProDictation(using: bridge, hasFullAccess: true)

        #expect(helper.openAppCount == 1)
        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.primaryActionTitle == "Open App for Pro Dictation")
        #expect(viewModel.workflowSummary == "Quick: apply the selected preset to text before the cursor. Pro: Open App records in the iPhone app. Paste Last inserts saved app text.")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.infoMessage == viewModel.workflowSummary)
    }

    @MainActor
    @Test func polishUsesCurrentTextBridgeForQuickMode() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = try! AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        settingsStore.update { settings in
            settings.outputPreset = .polishedMessage
        }

        let helper = KeyboardHelperSpy()
        helper.currentText = "draft text"
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: settingsStore, skipAppGroupSetup: true)

        viewModel.polishCurrentDraft(using: bridge)

        #expect(helper.replacedCurrentText?.original == "draft text")
        #expect(helper.replacedCurrentText?.replacement == "Draft text.")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.infoMessage == "Quick mode applied polished message to text before the cursor.")
    }

    @MainActor
    @Test func refreshKeyboardContextMarksQuickHintWhenTextBeforeCursorExists() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helper = KeyboardHelperSpy()
        helper.currentText = "draft text"
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.refreshKeyboardContext(using: bridge)

        #expect(viewModel.hasTextBeforeCursor)
        #expect(viewModel.quickReadinessTitle == "Text before cursor detected")
        #expect(viewModel.quickReadinessDetail == "Quick only transforms existing text before the cursor.")
    }

    @MainActor
    @Test func refreshPullsSharedSavedTextAndKeyboardContextWithoutPolling() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Saved from app", forKey: SharedContainerKeys.lastTranscriptionKey)

        let helper = KeyboardHelperSpy()
        helper.currentText = "draft text"
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.refresh(using: bridge)

        #expect(viewModel.latestTranscription == "Saved from app")
        #expect(viewModel.hasSavedResult)
        #expect(viewModel.hasTextBeforeCursor)
    }

    @MainActor
    @Test func refreshKeyboardContextShowsQuickNeedsTextWhenCursorContextIsEmpty() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helper = KeyboardHelperSpy()
        helper.currentText = "   "
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.refreshKeyboardContext(using: bridge)

        #expect(!viewModel.hasTextBeforeCursor)
        #expect(viewModel.quickReadinessTitle == "Quick needs text before cursor")
        #expect(viewModel.quickReadinessDetail == "Type or dictate first, then use Quick on text before the cursor.")
    }

    @MainActor
    @Test func polishReportsNoOpWhenPresetDoesNotChangeText() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helper = KeyboardHelperSpy()
        helper.currentText = "Already final."
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.polishCurrentDraft(using: bridge)

        #expect(helper.replacedCurrentText == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.infoMessage == "Quick mode found no changes before the cursor.")
    }

    @MainActor
    @Test func pasteLastUsesHelperBridgeToInsertSavedTranscription() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("From helper app", forKey: SharedContainerKeys.lastTranscriptionKey)

        let helper = KeyboardHelperSpy()
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.insertLastDictation(using: bridge)

        #expect(helper.insertedTexts == ["From helper app"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.infoMessage == "Inserted the latest transcription from the iPhone app.")
    }

    @MainActor
    @Test func savedResultRecommendationTracksSharedSavedText() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("From helper app", forKey: SharedContainerKeys.lastTranscriptionKey)

        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        #expect(viewModel.hasSavedResult)
        #expect(viewModel.shouldRecommendPasteLast)
        #expect(!viewModel.shouldRecommendProDictation)
    }

    @MainActor
    @Test func pasteLastRequiresSavedHostTranscription() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helper = KeyboardHelperSpy()
        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.insertLastDictation(using: bridge)

        #expect(helper.insertedTexts.isEmpty)
        #expect(viewModel.errorMessage == "No saved transcription yet. Use Open App for Pro Dictation first, then tap Paste Last.")
    }

    @MainActor
    @Test func hostAppLaunchFailureExplainsWhyKeyboardCouldNotOpenTheApp() {
        let suiteName = "voiceinput.tests.keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = KeyboardDictationViewModel(sharedDefaults: defaults, settingsStore: nil, skipAppGroupSetup: true)

        viewModel.reportHostAppLaunchFailure(hasFullAccess: true)

        #expect(viewModel.errorMessage == "Could not open the VoiceInput app from the keyboard. Open the app once and try again.")
    }
}

private final class KeyboardHelperSpy: KeyboardTextDocumentHelping {
    private(set) var insertedTexts: [String] = []
    private(set) var deleteBackwardCount = 0
    private(set) var advanceKeyboardCount = 0
    private(set) var openAppCount = 0
    var currentText: String?
    private(set) var replacedCurrentText: (original: String, replacement: String)?

    func insertTextIntoDocument(_ text: String) {
        insertedTexts.append(text)
    }

    func deleteBackwardInDocument() {
        deleteBackwardCount += 1
    }

    func advanceToNextKeyboardInputMode() {
        advanceKeyboardCount += 1
    }

    func openVoiceInputHostApp() {
        openAppCount += 1
    }

    func documentContextBeforeInputText() -> String? {
        currentText
    }

    func replaceTextBeforeCursor(currentText: String, with replacement: String) {
        replacedCurrentText = (currentText, replacement)
        self.currentText = replacement
    }
}
