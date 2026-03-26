import SwiftUI
import VoiceInputCore

struct IOSDictationView: View {
    @StateObject private var viewModel: IOSDictationViewModel
    @State private var glossarySearchText = ""
    @State private var correctionSearchText = ""
    @State private var isProcessingSettingsExpanded = false
    @State private var isGlossaryExpanded = false
    @State private var isCorrectionsExpanded = false
    @State private var isCandidateCorrectionsExpanded = false
    @State private var isQuickNoteHistoryExpanded = true
    @State private var isKeyboardHandoffExpanded = true
    @State private var didSeedReferenceSectionState = false
    @State private var userChangedQuickNoteHistoryExpansion = false
    @State private var userChangedKeyboardHandoffExpansion = false
    @FocusState private var focusedGlossaryField: GlossaryFocusField?
    @FocusState private var focusedCorrectionField: CorrectionFocusField?

    @MainActor
    init(viewModel: IOSDictationViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? IOSDictationViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    handoffStatusSection
                    recorderSection
                    feedbackSection
                    latestTranscriptionSection
                    suggestedFixesSection
                    quickNoteHistorySection
                    keyboardSetupSection
                    processingSettingsSection
                }
                .padding(20)
            }
            .onChange(of: viewModel.selectedLanguage) { _, _ in
                viewModel.persistSettings()
            }
            .onChange(of: viewModel.selectedModel) { _, _ in
                viewModel.persistSettings()
            }
            .onChange(of: viewModel.autoInsertText) { _, _ in
                viewModel.persistSettings()
            }
            .onChange(of: viewModel.keepQuickNoteHistory) { _, _ in
                viewModel.persistSettings()
            }
            .onChange(of: viewModel.outputPreset) { _, _ in
                viewModel.persistSettings()
            }
            .onChange(of: viewModel.candidateCorrections) { _, _ in
                viewModel.refreshSuppressedCandidateSuggestions()
            }
            .onChange(of: viewModel.transcribedText) { _, _ in
                viewModel.refreshSuppressedCandidateSuggestions()
            }
            .onOpenURL { url in
                viewModel.handleIncomingURL(url)
            }
            .onAppear {
                seedReferenceSectionStateIfNeeded()
            }
            .onChange(of: isActiveWorkflowFocusState) { _, isActive in
                collapseReferenceSectionsIfNeeded(for: isActive)
            }
            .navigationTitle("VoiceInput")
        }
    }

    private var heroSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("VoiceInput for iPhone")
                    .font(.largeTitle.bold())

                HStack(spacing: 8) {
                    modePill(title: "Pro in App", tint: .blue)
                    modePill(title: "Quick in Keyboard", tint: .purple)
                }

                HStack(spacing: 8) {
                    summaryBadge(title: viewModel.selectedLanguage.displayName, tint: .blue)
                    summaryBadge(title: viewModel.outputPreset.displayName, tint: .purple)
                    summaryBadge(title: viewModel.selectedModel, tint: .green)
                }
            }
        }
    }

    private var handoffStatusSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(handoffStatusTitle, systemImage: handoffStatusSymbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(handoffStatusTint)
                    Spacer()
                    if hasSavedResult {
                        Text("Saved for keyboard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(handoffStatusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(handoffStatusTint)
                    Text(handoffNextStep)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var recorderSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(viewModel.recordingState.statusText(), systemImage: recordingStateSymbolName)
                        .font(.headline)
                        .foregroundStyle(viewModel.recordingState.isRecording ? .red : .primary)
                    Spacer()
                    Text("Pro Mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("Pro mode records here. Quick mode only edits text before the cursor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.persistSettings()
                    viewModel.toggleRecording()
                } label: {
                    Text(viewModel.recordingState.isRecording ? "Stop & Transcribe" : "Start Dictation")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if hasFeedback {
            cardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    if let errorMessage = viewModel.errorMessage {
                        feedbackMessage(errorMessage, color: .red, systemImage: "exclamationmark.triangle.fill")
                    }

                    if let infoMessage = viewModel.infoMessage {
                        feedbackMessage(infoMessage, color: .blue, systemImage: "info.circle.fill")
                    }

                    if let setupErrorMessage = viewModel.setupErrorMessage {
                        feedbackMessage(setupErrorMessage, color: .orange, systemImage: "wrench.and.screwdriver.fill")
                    }

                    if viewModel.showOpenSettingsShortcut {
                        Button("Open iOS Settings") {
                            viewModel.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var latestTranscriptionSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Latest Transcription")
                        .font(.headline)
                    Spacer()
                    commitStatusBadge
                    if viewModel.canUpdatePasteLast {
                        Button("Update Paste Last") {
                            _ = viewModel.updatePasteLastFromCurrentDraft()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                TextEditor(text: $viewModel.transcribedText)
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if viewModel.hasUnsavedKeyboardEdits {
                    Text("Paste Last still uses the saved keyboard result until you update it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if viewModel.hasSavedKeyboardResult {
                    Text("Paste Last will use this saved result from the keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.hasSavedKeyboardResult {
                    savedKeyboardResultPreview
                }
            }
        }
    }

    @ViewBuilder
    private var suggestedFixesSection: some View {
        if !viewModel.suppressedCandidateSuggestions.isEmpty {
            cardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Suggested Fixes")
                            .font(.headline)
                        compactStateBadge(
                            title: "Review before Paste Last",
                            tint: .blue
                        )
                    }

                    Text("Optional low-confidence mixed-language fixes. Review them before you return to the keyboard if you want the saved result refined.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Apply in App updates both this draft and what Paste Last will use.")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    ForEach(Array(viewModel.suppressedCandidateSuggestions.enumerated()), id: \.offset) { index, candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(candidate.sourceText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("→ \(candidate.resolvedReplacement)")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button("Apply in App") {
                                    _ = viewModel.applySuppressedCandidateSuggestion(at: index)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Copy Corrected Text") {
                                    _ = viewModel.copySuppressedCandidateSuggestion(at: index)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!viewModel.canCopySuppressedCandidateSuggestion(at: index))

                                Button("Save as Rule") {
                                    _ = viewModel.saveSuppressedCandidateSuggestionAsRule(at: index)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!viewModel.canSaveSuppressedCandidateSuggestionAsRule(at: index))
                            }

                            HStack(spacing: 8) {
                                Text("Confidence \(Int(candidate.confidence * 100))%")
                                if let detail = candidate.evidence.detail,
                                   !detail.isEmpty
                                {
                                    Text(detail)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }
                }
                .padding(2)
            }
        }
    }

    private var quickNoteHistorySection: some View {
        cardContainer {
            DisclosureGroup(isExpanded: quickNoteHistoryExpansionBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.quickNoteHistory.isEmpty {
                        Text("No saved notes yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.quickNoteHistory.prefix(8), id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Quick Note History")
                                .font(.headline)
                            if isActiveWorkflowFocusState {
                                referenceBadge(title: "Reference")
                            }
                        }

                        Text(quickNoteHistorySummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !viewModel.quickNoteHistory.isEmpty && isQuickNoteHistoryExpanded {
                        Button("Clear") {
                            viewModel.clearQuickNoteHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var keyboardSetupSection: some View {
        cardContainer {
            DisclosureGroup(isExpanded: keyboardHandoffExpansionBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        workflowRow(label: "Setup", detail: "Add the VoiceInput keyboard and enable Full Access once.")
                        workflowRow(label: "Quick", detail: "Polish text before the cursor without leaving the current app.")
                        workflowRow(label: "Pro", detail: "Record here, then return to the keyboard and tap Paste Last.")
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Keyboard Handoff")
                            .font(.headline)
                        if isActiveWorkflowFocusState {
                            referenceBadge(title: "Reference")
                        }
                    }

                    Text(keyboardHandoffSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var processingSettingsSection: some View {
        cardContainer {
            DisclosureGroup(isExpanded: $isProcessingSettingsExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language")
                            .font(.subheadline.weight(.semibold))

                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(viewModel.supportedLanguages, id: \.rawValue) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.subheadline.weight(.semibold))

                        Picker("Model", selection: $viewModel.selectedModel) {
                            ForEach(viewModel.modelVariants, id: \.self) { variant in
                                Text(variant).tag(variant)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output Preset")
                            .font(.subheadline.weight(.semibold))

                        Picker("Output Preset", selection: $viewModel.outputPreset) {
                            ForEach(TranscriptionOutputPreset.allCases, id: \.rawValue) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Keyboard auto-insert after transcription", isOn: $viewModel.autoInsertText)
                        .font(.subheadline)

                    Toggle("Keep quick-note history", isOn: $viewModel.keepQuickNoteHistory)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Language Intelligence")
                            .font(.subheadline.weight(.semibold))
                        Text("Use glossary and local correction rules only when you need to tune output. Daily dictation stays above.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup(isExpanded: $isGlossaryExpanded) {
                        glossaryEditorSection
                            .padding(.top, 8)
                    } label: {
                        settingsGroupLabel(
                            title: "Glossary",
                            detail: viewModel.glossary.isEmpty ? "No saved terms" : "\(viewModel.glossary.count) saved terms",
                            purpose: "Preserve names and brands"
                        )
                    }

                    DisclosureGroup(isExpanded: $isCorrectionsExpanded) {
                        correctionsEditorSection
                            .padding(.top, 8)
                    } label: {
                        settingsGroupLabel(
                            title: "Exact Corrections",
                            detail: viewModel.corrections.isEmpty ? "No exact rules" : "\(viewModel.corrections.count) exact rules",
                            purpose: "Always replace exact mishears"
                        )
                    }

                    DisclosureGroup(isExpanded: $isCandidateCorrectionsExpanded) {
                        candidateCorrectionsEditorSection
                            .padding(.top, 8)
                    } label: {
                        settingsGroupLabel(
                            title: "Candidate Corrections",
                            detail: viewModel.candidateCorrections.isEmpty ? "No candidate rules" : "\(viewModel.candidateCorrections.count) candidate rules",
                            purpose: "Review low-confidence mixed-language fixes"
                        )
                    }
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Processing Settings")
                            .font(.headline)
                        Text("\(viewModel.selectedLanguage.displayName) · \(viewModel.outputPreset.displayName) · \(viewModel.selectedModel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(intelligenceSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Tune Output")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var glossaryEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add names, acronyms, and mixed-language terms you want Quick/Pro mode to preserve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Term") {
                    glossarySearchText = ""
                    viewModel.addGlossaryItem()
                }
                .font(.caption.weight(.semibold))
            }

            if !viewModel.glossary.isEmpty {
                glossarySearchField
            }

            if viewModel.glossary.isEmpty {
                Text("No glossary terms yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if visibleGlossaryIndices.isEmpty {
                Text("No glossary terms match this search.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleGlossaryIndices, id: \.self) { index in
                    let rowSearchMatches = searchMatches(for: index)
                    let rowSuggestedAliasPreview = suggestedAliasPreview(for: index)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Phrase", text: glossaryBinding(index).phrase)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedGlossaryField, equals: .phrase(index))
                            Button {
                                viewModel.removeGlossaryItem(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }

                        TextField("Replacement", text: glossaryBinding(index).replacement)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedGlossaryField, equals: .replacement(index))
                        TextField("Aliases (comma separated)", text: aliasBinding(for: index))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedGlossaryField, equals: .aliases(index))
                        if !rowSearchMatches.isEmpty {
                            GlossarySearchMatchView(
                                matches: Array(rowSearchMatches.prefix(2)),
                                overflowCount: max(0, rowSearchMatches.count - 2)
                            )
                        }
                        if !rowSuggestedAliasPreview.isEmpty {
                            GlossarySuggestedAliasesView(
                                preview: rowSuggestedAliasPreview
                            )
                        }
                        Text("Common English variants like open ai, open-ai, and open.ai are inferred automatically from the phrase or replacement.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
    }

    private var correctionsEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add exact local fixes for phrases Whisper consistently hears wrong, such as chat gp t -> ChatGPT.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Rule") {
                    correctionSearchText = ""
                    viewModel.addCorrectionRule()
                }
                .font(.caption.weight(.semibold))
            }

            if !viewModel.corrections.isEmpty {
                correctionSearchField
            }

            if viewModel.corrections.isEmpty {
                Text("No correction rules yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if visibleCorrectionIndices.isEmpty {
                Text("No correction rules match this search.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleCorrectionIndices, id: \.self) { index in
                    let rowSearchMatches = correctionSearchMatches(for: index)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Heard phrase", text: correctionSourceBinding(index))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedCorrectionField, equals: .source(index))
                            Button {
                                viewModel.removeCorrectionRule(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }

                        TextField("Replace with", text: correctionReplacementBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedCorrectionField, equals: .replacement(index))

                        if !rowSearchMatches.isEmpty {
                            CorrectionSearchMatchView(
                                matches: Array(rowSearchMatches.prefix(2)),
                                overflowCount: max(0, rowSearchMatches.count - 2)
                            )
                        }

                        Text("These exact replacements run locally before glossary and preset formatting.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
    }

    private var candidateCorrectionsEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Use confidence-gated local replacements for mixed-language phrases Whisper gets close to but not consistently enough for an always-on exact correction.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Rule") {
                    viewModel.addCandidateCorrectionRule()
                }
                .font(.caption.weight(.semibold))
            }

            Text("Add source aliases when the same term is misheard in multiple ways.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if viewModel.candidateCorrections.isEmpty {
                Text("No candidate correction rules yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.candidateCorrections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Heard phrase", text: candidateCorrectionSourceBinding(index))
                                .textFieldStyle(.roundedBorder)
                            Button {
                                viewModel.removeCandidateCorrectionRule(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }

                        TextField("Source aliases (comma separated)", text: candidateCorrectionAliasesBinding(index))
                            .textFieldStyle(.roundedBorder)

                        TextField("Replace with", text: candidateCorrectionReplacementBinding(index))
                            .textFieldStyle(.roundedBorder)

                        TextField("Evidence note (optional)", text: candidateCorrectionEvidenceDetailBinding(index))
                            .textFieldStyle(.roundedBorder)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Candidate confidence")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(candidateCorrectionConfidenceLabel(index))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: candidateCorrectionConfidenceBinding(index),
                                in: 0...1,
                                step: 0.05
                            )
                        }

                        Picker("Auto Apply", selection: candidateCorrectionAutoApplyStrategyBinding(index)) {
                            Text("Never").tag(TranscriptionCandidateAutoApplyPolicy.Strategy.never)
                            Text("Always").tag(TranscriptionCandidateAutoApplyPolicy.Strategy.always)
                            Text("Threshold").tag(TranscriptionCandidateAutoApplyPolicy.Strategy.ifConfidenceAtLeast)
                        }
                        .pickerStyle(.segmented)

                        if candidateCorrectionAutoApplyStrategy(for: index) == .ifConfidenceAtLeast {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Auto-apply threshold")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(candidateCorrectionThresholdLabel(index))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Slider(
                                    value: candidateCorrectionMinimumConfidenceBinding(index),
                                    in: 0...1,
                                    step: 0.05
                                )
                            }
                        }

                        Text("Candidate rules also match common separator variants and conservative Korean/Japanese particle attachments. Low-confidence candidates stay visible to the processor but will not auto-apply.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
    }

    private var hasFeedback: Bool {
        viewModel.errorMessage != nil
            || viewModel.infoMessage != nil
            || viewModel.setupErrorMessage != nil
            || viewModel.showOpenSettingsShortcut
    }

    private var hasSavedResult: Bool {
        viewModel.hasSavedKeyboardResult
    }

    private var isActiveWorkflowFocusState: Bool {
        if viewModel.recordingState != .idle {
            return true
        }

        if hasSavedResult || viewModel.hasUnsavedKeyboardEdits {
            return true
        }

        return !viewModel.suppressedCandidateSuggestions.isEmpty
    }

    private var quickNoteHistorySummary: String {
        if viewModel.quickNoteHistory.isEmpty {
            return isActiveWorkflowFocusState
                ? "Reference only while you review the current result."
                : "No saved notes yet."
        }

        let count = viewModel.quickNoteHistory.count
        if isActiveWorkflowFocusState {
            return "\(count) saved notes. Expand only if you need older context."
        }

        return "\(count) saved notes."
    }

    private var keyboardHandoffSummary: String {
        if isActiveWorkflowFocusState {
            return "Quick edits before the cursor. Pro saves text for Paste Last."
        }

        return "One setup step, then Quick and Pro stay ready."
    }

    private var handoffStatusTitle: String {
        switch viewModel.recordingState {
        case .recording:
            return "Recording in progress"
        case .transcribing, .inserting:
            return "Preparing app result"
        case .error:
            return "Action needed"
        case .idle:
            if !hasSavedResult {
                return "No saved result yet"
            }
            if viewModel.hasUnsavedKeyboardEdits {
                return "Unsaved edits in draft"
            }
            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                return "Review fixes before returning"
            }
            return "Ready for Paste Last"
        }
    }

    private var handoffStatusDetail: String {
        switch viewModel.recordingState {
        case .recording:
            return "Finish this pass in the app before returning to the keyboard."
        case .transcribing, .inserting:
            return "VoiceInput is saving the latest app result for keyboard reuse."
        case .error:
            return "A setup or permission issue needs attention before the keyboard can reuse this result."
        case .idle:
            if !hasSavedResult {
                return "Quick edits existing keyboard text. Pro creates the saved result."
            }
            if viewModel.hasUnsavedKeyboardEdits {
                return "The editor has newer text than the saved keyboard result."
            }
            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                return "A saved result exists, but manual fixes are available before you paste it."
            }
            return "The latest app result is saved and ready for the keyboard."
        }
    }

    private var handoffNextStep: String {
        switch viewModel.recordingState {
        case .recording:
            return "Tap Stop & Transcribe when you're done speaking."
        case .transcribing, .inserting:
            return "Stay here until the saved result finishes updating."
        case .error:
            return viewModel.showOpenSettingsShortcut
                ? "Open Settings or fix the message below, then try again."
                : "Fix the message below, then try again."
        case .idle:
            if !hasSavedResult {
                return "Tap Start Dictation once, then return to the keyboard."
            }
            if viewModel.hasUnsavedKeyboardEdits {
                return "Tap Update Paste Last before returning to the keyboard."
            }
            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                return "Apply fixes now, or return and Paste Last."
            }
            return "Return to the keyboard and tap Paste Last."
        }
    }

    private var handoffStatusTint: Color {
        switch viewModel.recordingState {
        case .recording:
            return .red
        case .transcribing, .inserting:
            return .orange
        case .error:
            return .orange
        case .idle:
            if !hasSavedResult {
                return .secondary
            }
            if viewModel.hasUnsavedKeyboardEdits {
                return .orange
            }
            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                return .orange
            }
            return .green
        }
    }

    private var handoffStatusSymbolName: String {
        switch viewModel.recordingState {
        case .recording:
            return "record.circle.fill"
        case .transcribing, .inserting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        case .idle:
            if !hasSavedResult {
                return "tray"
            }
            if viewModel.hasUnsavedKeyboardEdits {
                return "square.and.arrow.down.badge.exclamationmark"
            }
            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                return "wand.and.stars.inverse"
            }
            return "checkmark.circle.fill"
        }
    }

    private var intelligenceSummary: String {
        let glossaryCount = viewModel.glossary.count
        let exactCount = viewModel.corrections.count
        let candidateCount = viewModel.candidateCorrections.count

        guard glossaryCount + exactCount + candidateCount > 0 else {
            return "No glossary or correction tuning yet"
        }

        return "\(glossaryCount) glossary · \(exactCount) exact · \(candidateCount) candidate"
    }

    private var recordingStateSymbolName: String {
        viewModel.recordingState.statusSymbolName
    }

    private func feedbackMessage(_ text: String, color: Color, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(color)
    }

    private func settingsGroupLabel(title: String, detail: String, purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(purpose)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func modePill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func workflowRow(label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func referenceBadge(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private var commitStatusBadge: some View {
        Text(commitStatusTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(commitStatusTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(commitStatusTint.opacity(0.12))
            )
    }

    private var savedKeyboardResultPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Paste Last Uses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !viewModel.suppressedCandidateSuggestions.isEmpty {
                    compactStateBadge(
                        title: "Pending optional review",
                        tint: .secondary
                    )
                } else if viewModel.hasUnsavedKeyboardEdits {
                    compactStateBadge(
                        title: "Older saved version",
                        tint: .orange
                    )
                } else {
                    compactStateBadge(
                        title: "Matches current draft",
                        tint: .green
                    )
                }

                Spacer()

                Button("Copy Saved Result") {
                    _ = viewModel.copySavedKeyboardResult()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(viewModel.savedKeyboardText)
                .font(.footnote)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)

            Text(
                savedKeyboardPreviewDetail
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(savedKeyboardPreviewBackgroundTint)
        )
    }

    private var commitStatusTitle: String {
        if viewModel.hasUnsavedKeyboardEdits {
            return "Unsaved edits"
        }
        if viewModel.hasSavedKeyboardResult {
            return "Saved for keyboard"
        }
        return "Not saved"
    }

    private var commitStatusTint: Color {
        if viewModel.hasUnsavedKeyboardEdits {
            return .orange
        }
        if viewModel.hasSavedKeyboardResult {
            return .green
        }
        return .secondary
    }

    private var savedKeyboardPreviewDetail: String {
        if !viewModel.suppressedCandidateSuggestions.isEmpty {
            return "A saved result exists, but these optional fixes can refine it before you paste."
        }

        if viewModel.hasUnsavedKeyboardEdits {
            return "Paste Last still inserts this saved version until you update it."
        }

        return "Paste Last will insert this saved version."
    }

    private var savedKeyboardPreviewBackgroundTint: Color {
        if !viewModel.suppressedCandidateSuggestions.isEmpty {
            return Color.secondary.opacity(0.04)
        }

        return Color.secondary.opacity(0.06)
    }

    private func compactStateBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func cardContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func summaryBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private var quickNoteHistoryExpansionBinding: Binding<Bool> {
        Binding(
            get: { isQuickNoteHistoryExpanded },
            set: { newValue in
                userChangedQuickNoteHistoryExpansion = true
                isQuickNoteHistoryExpanded = newValue
            }
        )
    }

    private var keyboardHandoffExpansionBinding: Binding<Bool> {
        Binding(
            get: { isKeyboardHandoffExpanded },
            set: { newValue in
                userChangedKeyboardHandoffExpansion = true
                isKeyboardHandoffExpanded = newValue
            }
        )
    }

    private func seedReferenceSectionStateIfNeeded() {
        guard !didSeedReferenceSectionState else {
            return
        }

        let shouldCollapse = isActiveWorkflowFocusState
        isQuickNoteHistoryExpanded = !shouldCollapse
        isKeyboardHandoffExpanded = !shouldCollapse
        didSeedReferenceSectionState = true
    }

    private func collapseReferenceSectionsIfNeeded(for isActive: Bool) {
        guard didSeedReferenceSectionState, isActive else {
            return
        }

        if !userChangedQuickNoteHistoryExpansion {
            isQuickNoteHistoryExpanded = false
        }

        if !userChangedKeyboardHandoffExpansion {
            isKeyboardHandoffExpanded = false
        }
    }

    private var glossarySearchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search glossary", text: $glossarySearchText)
                    .textFieldStyle(.roundedBorder)
                if !glossarySearchText.isEmpty {
                    Button {
                        glossarySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Search phrase, replacement, aliases, and suggested aliases.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var correctionSearchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search corrections", text: $correctionSearchText)
                    .textFieldStyle(.roundedBorder)
                if !correctionSearchText.isEmpty {
                    Button {
                        correctionSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Search heard phrases and replacements.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var visibleGlossaryIndices: [Int] {
        let indices = Array(viewModel.glossary.indices)
        let query = glossarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return indices
        }

        return indices.filter { index in
            if focusedGlossaryField?.index == index {
                return true
            }
            return viewModel.glossary[index].matchesSearchQuery(query)
        }
    }

    private var visibleCorrectionIndices: [Int] {
        let indices = Array(viewModel.corrections.indices)
        let query = correctionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return indices
        }

        return indices.filter { index in
            if focusedCorrectionField?.index == index {
                return true
            }
            return viewModel.corrections[index].matchesSearchQuery(query)
        }
    }

    private func glossaryBinding(_ index: Int) -> Binding<TranscriptionGlossaryItem> {
        Binding(
            get: {
                guard viewModel.glossary.indices.contains(index) else {
                    return TranscriptionGlossaryItem(phrase: "", replacement: "", aliases: [])
                }
                return viewModel.glossary[index]
            },
            set: { updated in
                guard viewModel.glossary.indices.contains(index) else {
                    return
                }
                viewModel.glossary[index] = updated
                viewModel.persistSettings()
            }
        )
    }

    private func aliasBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.glossary.indices.contains(index) else {
                    return ""
                }
                return viewModel.glossary[index].aliases.joined(separator: ", ")
            },
            set: { updated in
                guard viewModel.glossary.indices.contains(index) else {
                    return
                }
                viewModel.glossary[index].aliases = updated
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                viewModel.persistSettings()
            }
        )
    }

    private func suggestedAliasPreview(for index: Int) -> TranscriptionGlossaryAliasSuggestionPreview {
        guard viewModel.glossary.indices.contains(index) else {
            return TranscriptionGlossaryAliasSuggestionPreview(visibleAliases: [], overflowCount: 0)
        }
        return viewModel.glossary[index].aliasSuggestionPreview(limit: 3)
    }

    private func correctionSourceBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.corrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.corrections[index].source
            },
            set: { updated in
                guard viewModel.corrections.indices.contains(index) else {
                    return
                }
                viewModel.corrections[index].source = updated
                viewModel.persistSettings()
            }
        )
    }

    private func correctionReplacementBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.corrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.corrections[index].replacement
            },
            set: { updated in
                guard viewModel.corrections.indices.contains(index) else {
                    return
                }
                viewModel.corrections[index].replacement = updated
                viewModel.persistSettings()
            }
        )
    }

    private func correctionSearchMatches(for index: Int) -> [TranscriptionCorrectionSearchMatch] {
        guard viewModel.corrections.indices.contains(index) else {
            return []
        }

        let query = correctionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return viewModel.corrections[index].searchMatches(for: query)
    }

    private func candidateCorrectionSourceBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.candidateCorrections[index].source
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].source = updated
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionReplacementBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.candidateCorrections[index].replacement
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].replacement = updated
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionAliasesBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.candidateCorrections[index].aliases.joined(separator: ", ")
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].aliases = parseCandidateAliases(from: updated)
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionEvidenceDetailBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.candidateCorrections[index].evidence.detail ?? ""
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].evidence = TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: updated
                )
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionConfidenceBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return 0
                }
                return viewModel.candidateCorrections[index].confidence
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].confidence = updated
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionAutoApplyStrategyBinding(
        _ index: Int
    ) -> Binding<TranscriptionCandidateAutoApplyPolicy.Strategy> {
        Binding(
            get: { candidateCorrectionAutoApplyStrategy(for: index) },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }

                let existingThreshold =
                    viewModel.candidateCorrections[index].autoApplyPolicy.minimumConfidence
                    ?? viewModel.candidateCorrections[index].confidence

                switch updated {
                case .never:
                    viewModel.candidateCorrections[index].autoApplyPolicy = .never
                case .always:
                    viewModel.candidateCorrections[index].autoApplyPolicy = .always
                case .ifConfidenceAtLeast:
                    viewModel.candidateCorrections[index].autoApplyPolicy = .ifConfidenceAtLeast(existingThreshold)
                }

                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionMinimumConfidenceBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return 1
                }
                return viewModel.candidateCorrections[index].autoApplyPolicy.minimumConfidence
                    ?? viewModel.candidateCorrections[index].confidence
            },
            set: { updated in
                guard viewModel.candidateCorrections.indices.contains(index) else {
                    return
                }
                viewModel.candidateCorrections[index].autoApplyPolicy = .ifConfidenceAtLeast(updated)
                viewModel.persistSettings()
            }
        )
    }

    private func candidateCorrectionAutoApplyStrategy(
        for index: Int
    ) -> TranscriptionCandidateAutoApplyPolicy.Strategy {
        guard viewModel.candidateCorrections.indices.contains(index) else {
            return .never
        }
        return viewModel.candidateCorrections[index].autoApplyPolicy.strategy
    }

    private func candidateCorrectionConfidenceLabel(_ index: Int) -> String {
        guard viewModel.candidateCorrections.indices.contains(index) else {
            return "0%"
        }
        return viewModel.candidateCorrections[index].confidence.formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    private func candidateCorrectionThresholdLabel(_ index: Int) -> String {
        guard viewModel.candidateCorrections.indices.contains(index) else {
            return "100%"
        }
        let threshold = viewModel.candidateCorrections[index].autoApplyPolicy.minimumConfidence
            ?? viewModel.candidateCorrections[index].confidence
        return threshold.formatted(.percent.precision(.fractionLength(0)))
    }

    private func parseCandidateAliases(from value: String) -> [String] {
        value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func searchMatches(for index: Int) -> [TranscriptionGlossarySearchMatch] {
        guard viewModel.glossary.indices.contains(index) else {
            return []
        }

        let query = glossarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return viewModel.glossary[index].searchMatches(for: query)
    }

    private enum GlossaryFocusField: Hashable {
        case phrase(Int)
        case replacement(Int)
        case aliases(Int)

        var index: Int {
            switch self {
            case .phrase(let index), .replacement(let index), .aliases(let index):
                return index
            }
        }
    }

    private enum CorrectionFocusField: Hashable {
        case source(Int)
        case replacement(Int)

        var index: Int {
            switch self {
            case .source(let index), .replacement(let index):
                return index
            }
        }
    }
}

private struct GlossarySuggestedAliasesView: View {
    let preview: TranscriptionGlossaryAliasSuggestionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested aliases")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(preview.visibleAliases, id: \.self) { alias in
                        Text(alias)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }

                    if preview.overflowCount > 0 {
                        Text("+\(preview.overflowCount) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct GlossarySearchMatchView: View {
    let matches: [TranscriptionGlossarySearchMatch]
    let overflowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matched on")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                        highlightedMatchText(match)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.blue.opacity(0.10))
                            )
                    }

                    if overflowCount > 0 {
                        Text("+\(overflowCount) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func highlightedMatchText(_ match: TranscriptionGlossarySearchMatch) -> Text {
        let prefix = Text("\(match.source.displayName): ")
        guard
            let highlight = match.highlight,
            let segments = highlightedSegments(in: match.value, highlight: highlight)
        else {
            return prefix + Text(match.value)
        }

        return prefix
            + Text(segments.prefix)
            + Text(segments.highlight)
                .foregroundColor(.blue)
                .bold()
            + Text(segments.suffix)
    }

    private func highlightedSegments(
        in value: String,
        highlight: TranscriptionGlossarySearchHighlight
    ) -> (prefix: String, highlight: String, suffix: String)? {
        guard highlight.location >= 0, highlight.length > 0 else {
            return nil
        }

        guard let start = value.index(
            value.startIndex,
            offsetBy: highlight.location,
            limitedBy: value.endIndex
        ) else {
            return nil
        }

        guard let end = value.index(
            start,
            offsetBy: highlight.length,
            limitedBy: value.endIndex
        ) else {
            return nil
        }

        return (
            prefix: String(value[..<start]),
            highlight: String(value[start..<end]),
            suffix: String(value[end...])
        )
    }
}

private struct CorrectionSearchMatchView: View {
    let matches: [TranscriptionCorrectionSearchMatch]
    let overflowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matched on")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                        highlightedMatchText(match)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.green.opacity(0.10))
                            )
                    }

                    if overflowCount > 0 {
                        Text("+\(overflowCount) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func highlightedMatchText(_ match: TranscriptionCorrectionSearchMatch) -> Text {
        let prefix = Text("\(match.source.displayName): ")
        guard
            let highlight = match.highlight,
            let segments = highlightedSegments(in: match.value, highlight: highlight)
        else {
            return prefix + Text(match.value)
        }

        return prefix
            + Text(segments.prefix)
            + Text(segments.highlight)
                .foregroundColor(.green)
                .bold()
            + Text(segments.suffix)
    }

    private func highlightedSegments(
        in value: String,
        highlight: TranscriptionCorrectionSearchHighlight
    ) -> (prefix: String, highlight: String, suffix: String)? {
        guard highlight.location >= 0, highlight.length > 0 else {
            return nil
        }

        guard let start = value.index(
            value.startIndex,
            offsetBy: highlight.location,
            limitedBy: value.endIndex
        ) else {
            return nil
        }

        guard let end = value.index(
            start,
            offsetBy: highlight.length,
            limitedBy: value.endIndex
        ) else {
            return nil
        }

        return (
            prefix: String(value[..<start]),
            highlight: String(value[start..<end]),
            suffix: String(value[end...])
        )
    }
}
