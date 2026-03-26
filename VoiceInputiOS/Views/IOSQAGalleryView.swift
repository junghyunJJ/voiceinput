import SwiftUI
import VoiceInputCore
import VoiceInputMobileShared

enum IOSQALaunchRoute: Equatable {
    case none
    case gallery
    case host(IOSQAHostState)
    case keyboardGallery

    static func resolve(arguments: [String]) -> IOSQALaunchRoute {
        if let hostIndex = arguments.firstIndex(of: "--qa-host-state"),
           arguments.indices.contains(hostIndex + 1),
           let state = IOSQAHostState(rawValue: arguments[hostIndex + 1]) {
            return .host(state)
        }

        if arguments.contains("--qa-keyboard-gallery") {
            return .keyboardGallery
        }

        if arguments.contains("--qa-gallery") {
            return .gallery
        }

        return .none
    }
}

struct IOSQAGalleryView: View {
    @State private var selectedScreen: IOSQAScreen?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introSection
                hostStateSection
                keyboardSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .fullScreenCover(item: $selectedScreen) { screen in
            IOSQAScreenContainer(screen: screen)
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deterministic QA Gallery")
                .font(.largeTitle.bold())

            Text("Use this debug-only gallery to inspect fixed host and keyboard states without relying on live recording, App Group state, or the keyboard extension runtime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var hostStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Host App States")
                .font(.headline)

            ForEach(IOSQAHostState.allCases) { state in
                galleryButton(
                    title: state.title,
                    subtitle: state.subtitle,
                    action: { selectedScreen = .host(state) }
                )
            }
        }
    }

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard States")
                .font(.headline)

            galleryButton(
                title: "Keyboard QA Gallery",
                subtitle: "Opens deterministic helper-only keyboard states inside the host app.",
                action: { selectedScreen = .keyboardGallery }
            )
        }
    }

    private func galleryButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum IOSQAScreen: Identifiable {
    case host(IOSQAHostState)
    case keyboardGallery

    var id: String {
        switch self {
        case .host(let state):
            return "host-\(state.rawValue)"
        case .keyboardGallery:
            return "keyboard-gallery"
        }
    }
}

private struct IOSQAScreenContainer: View {
    let screen: IOSQAScreen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            screenContent
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case .host(let state):
            IOSQAHostStateScreen(state: state)
        case .keyboardGallery:
            IOSQAKeyboardGalleryView()
        }
    }
}

struct IOSQAHostStateScreen: View {
    private let state: IOSQAHostState
    private let viewModel: IOSDictationViewModel

    @MainActor
    init(state: IOSQAHostState) {
        self.state = state
        self.viewModel = IOSQAHostStateFactory.makeViewModel(for: state)
    }

    var body: some View {
        IOSDictationView(viewModel: viewModel)
    }
}

enum IOSQAHostState: String, CaseIterable, Identifiable, Equatable {
    case idleNoSavedResult
    case savedResultReady
    case unsavedDraftEdits
    case suggestedFixes
    case recording
    case transcribing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idleNoSavedResult:
            return "Idle / No Saved Result"
        case .savedResultReady:
            return "Saved Result Ready"
        case .unsavedDraftEdits:
            return "Unsaved Draft Edits"
        case .suggestedFixes:
            return "Suggested Fixes Review"
        case .recording:
            return "Recording In Progress"
        case .transcribing:
            return "Transcribing"
        }
    }

    var subtitle: String {
        switch self {
        case .idleNoSavedResult:
            return "Default idle state before any Pro Dictation has created a saved keyboard result."
        case .savedResultReady:
            return "Saved keyboard text is ready, and the draft matches what Paste Last will insert."
        case .unsavedDraftEdits:
            return "The draft was edited locally, but Paste Last still uses the older saved version."
        case .suggestedFixes:
            return "A low-confidence mixed-language candidate is available for optional manual review."
        case .recording:
            return "Pro Dictation is actively recording in the host app."
        case .transcribing:
            return "Recording stopped and transcription is in progress."
        }
    }
}

private enum IOSQAHostStateFactory {
    @MainActor
    static func makeViewModel(for state: IOSQAHostState) -> IOSDictationViewModel {
        let suiteName = "voiceinput.qa.host.\(state.rawValue)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = try! AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        settingsStore.update { settings in
            settings.selectedLanguage = .auto
            settings.selectedModel = MobileConstants.Transcription.defaultModel
            settings.outputPreset = .polishedMessage
            settings.keepQuickNoteHistory = true
        }

        switch state {
        case .savedResultReady, .unsavedDraftEdits:
            defaults.set("Saved from app after Pro Dictation.", forKey: MobileConstants.lastTranscriptionKey)
        case .suggestedFixes:
            defaults.set("chat gp t에서 확인", forKey: MobileConstants.lastTranscriptionKey)
        case .idleNoSavedResult, .recording, .transcribing:
            break
        }

        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: settingsStore,
            skipAppGroupSetup: true,
            copyToClipboard: { _ in }
        )

        viewModel.quickNoteHistory = [
            "[3/11/2026, 9:14 AM] Quick note alpha.",
            "[3/11/2026, 9:12 AM] Quick note beta.",
        ]

        switch state {
        case .idleNoSavedResult:
            break
        case .savedResultReady:
            break
        case .unsavedDraftEdits:
            viewModel.transcribedText = "Saved from app after Pro Dictation, with manual edits."
        case .suggestedFixes:
            viewModel.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: ["chat-gp-t"],
                    replacement: "ChatGPT",
                    confidence: 0.62,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "mixed-language QA state"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            viewModel.transcribedText = "chat gp t에서 확인"
            viewModel.refreshSuppressedCandidateSuggestions()
        case .recording:
            viewModel.recordingState = .recording(startTime: Date().addingTimeInterval(-18))
        case .transcribing:
            viewModel.recordingState = .transcribing
        }

        return viewModel
    }
}

struct IOSQAKeyboardGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keyboard QA States")
                    .font(.largeTitle.bold())

                Text("These previews render the production keyboard view with deterministic helper-only state seeded inside the host app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(IOSQAKeyboardScenario.allCases) { scenario in
                    IOSQAKeyboardPreviewCard(seed: .make(for: scenario))
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct IOSQAKeyboardPreviewCard: View {
    let seed: IOSQAKeyboardSeed

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(seed.title)
                .font(.headline)

            Text(seed.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            KeyboardRootView(
                helperBridge: seed.bridge,
                hasFullAccess: seed.hasFullAccess,
                viewModel: seed.viewModel
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private enum IOSQAKeyboardScenario: String, CaseIterable, Identifiable {
    case noSavedResult
    case savedResultReady
    case quickAvailable
    case fullAccessBlocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noSavedResult:
            return "Pro First"
        case .savedResultReady:
            return "Paste Last Ready"
        case .quickAvailable:
            return "Quick Text Available"
        case .fullAccessBlocked:
            return "Full Access Blocked"
        }
    }

    var subtitle: String {
        switch self {
        case .noSavedResult:
            return "No saved app result yet, so Pro Dictation stays primary."
        case .savedResultReady:
            return "A saved app result exists, so Paste Last becomes primary."
        case .quickAvailable:
            return "Text exists before the cursor, so Quick polish can run in place."
        case .fullAccessBlocked:
            return "A saved result exists, but Full Access is off, so recovery guidance remains visible."
        }
    }
}

private struct IOSQAKeyboardSeed {
    let title: String
    let subtitle: String
    let helper: IOSQAKeyboardFakeHelper
    let bridge: KeyboardTextDocumentHelperBridge
    let viewModel: KeyboardDictationViewModel
    let hasFullAccess: Bool

    @MainActor
    static func make(for scenario: IOSQAKeyboardScenario) -> IOSQAKeyboardSeed {
        let suiteName = "voiceinput.qa.keyboard.\(scenario.rawValue)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = try! AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        settingsStore.update { settings in
            settings.outputPreset = .polishedMessage
            settings.selectedLanguage = .english
        }

        let helper = IOSQAKeyboardFakeHelper()
        let hasFullAccess: Bool

        switch scenario {
        case .noSavedResult:
            hasFullAccess = true
        case .savedResultReady:
            hasFullAccess = true
            defaults.set("Saved from app after Pro Dictation.", forKey: SharedContainerKeys.lastTranscriptionKey)
        case .quickAvailable:
            hasFullAccess = true
            helper.currentText = "draft text from chat"
        case .fullAccessBlocked:
            hasFullAccess = false
            defaults.set("Saved from app after Pro Dictation.", forKey: SharedContainerKeys.lastTranscriptionKey)
        }

        let bridge = KeyboardTextDocumentHelperBridge(helper: helper)
        let viewModel = KeyboardDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: settingsStore,
            skipAppGroupSetup: true
        )
        viewModel.refreshKeyboardContext(using: bridge)

        return IOSQAKeyboardSeed(
            title: scenario.title,
            subtitle: scenario.subtitle,
            helper: helper,
            bridge: bridge,
            viewModel: viewModel,
            hasFullAccess: hasFullAccess
        )
    }
}

private final class IOSQAKeyboardFakeHelper: KeyboardTextDocumentHelping {
    var currentText: String?

    func insertTextIntoDocument(_ text: String) {}
    func deleteBackwardInDocument() {}
    func advanceToNextKeyboardInputMode() {}
    func openVoiceInputHostApp() {}
    func documentContextBeforeInputText() -> String? { currentText }

    func replaceTextBeforeCursor(currentText: String, with replacement: String) {
        self.currentText = replacement
    }
}
