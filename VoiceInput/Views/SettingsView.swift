import Carbon
import SwiftUI
import VoiceInputCore

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelTab(viewModel: viewModel)
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            ProcessingTab(viewModel: viewModel)
                .tabItem {
                    Label("Output", systemImage: "wand.and.stars")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Recording Shortcut:")
                    Spacer()
                    ShortcutRecorderView(
                        displayText: viewModel.hotkeyManager.currentShortcut.displayString,
                        onShortcutCaptured: { keyCode, modifiers in
                            let newShortcut = HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
                            viewModel.hotkeyManager.updateShortcut(newShortcut)
                        }
                    )
                }

                HStack {
                    Text("Copy Last Transcription:")
                    Spacer()
                    ShortcutRecorderView(
                        displayText: viewModel.settings.copyActionShortcut.displayString,
                        onShortcutCaptured: { keyCode, modifiers in
                            let shortcut = CopyActionShortcut(
                                keyCode: keyCode,
                                modifiers: modifiers
                            )
                            viewModel.updateCopyActionShortcut(shortcut)
                        }
                    )
                }

                Picker("Mode:", selection: Binding(
                    get: { viewModel.settings.hotkeyMode },
                    set: { viewModel.updateHotkeyMode($0) }
                )) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Default: Option+Space. May conflict with Raycast/Alfred — change if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Copy shortcut is global and works from any app. Default: ⌘⇧C.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = viewModel.hotkeyManager.registrationWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Language") {
                Picker("Transcription Language:", selection: $viewModel.settings.selectedLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Auto-insert text at cursor", isOn: $viewModel.settings.autoInsertText)
                Toggle("Show recording overlay", isOn: $viewModel.settings.showOverlay)
                Toggle("Play sound effects", isOn: $viewModel.settings.playSound)

                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.settings.launchAtLogin },
                    set: { _ in viewModel.toggleLaunchAtLogin() }
                ))
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: viewModel.permissions.microphoneGranted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(viewModel.permissions.microphoneGranted ? .green : .red)
                    Text("Microphone")
                    Spacer()
                    if !viewModel.permissions.microphoneGranted {
                        Button("Grant") {
                            Task { await viewModel.permissions.requestMicrophonePermission() }
                        }
                    }
                }

                HStack {
                    Image(systemName: viewModel.permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(viewModel.permissions.accessibilityGranted ? .green : .red)
                    Text("Accessibility")
                    Spacer()
                    if !viewModel.permissions.accessibilityGranted {
                        Button("Open Settings") {
                            viewModel.permissions.openAccessibilitySettings()
                        }
                    }
                }

                Button("Refresh Permissions") {
                    viewModel.permissions.refreshPermissions()
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProcessingTab: View {
    @Bindable var viewModel: AppViewModel
    @State private var glossarySearchText = ""
    @State private var correctionSearchText = ""
    @FocusState private var focusedGlossaryField: GlossaryFocusField?
    @FocusState private var focusedCorrectionField: CorrectionFocusField?

    var body: some View {
        Form {
            Section("Output Preset") {
                Picker("Preset", selection: $viewModel.settings.outputPreset) {
                    ForEach(TranscriptionOutputPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Text("Verbatim preserves the raw transcript. Other presets apply deterministic local formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Glossary") {
                if !viewModel.settings.transcriptionGlossary.isEmpty {
                    glossarySearchField
                }

                if viewModel.settings.transcriptionGlossary.isEmpty {
                    Text("Add names, acronyms, and mixed-language terms you want VoiceInput to preserve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if visibleGlossaryIndices.isEmpty {
                    Text("No glossary terms match this search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(visibleGlossaryIndices, id: \.self) { index in
                    let rowSearchMatches = searchMatches(for: index)
                    let rowSuggestedAliasPreview = suggestedAliasPreview(for: index)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Phrase", text: glossaryBinding(index).phrase)
                                .focused($focusedGlossaryField, equals: .phrase(index))
                            Button {
                                removeGlossaryItem(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }

                        TextField("Replacement", text: glossaryBinding(index).replacement)
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
                    .padding(.vertical, 4)
                }

                Button("Add Glossary Term") {
                    glossarySearchText = ""
                    var glossary = viewModel.settings.transcriptionGlossary
                    glossary.append(
                        TranscriptionGlossaryItem(
                            phrase: "",
                            replacement: "",
                            aliases: []
                        )
                    )
                    viewModel.settings.transcriptionGlossary = glossary
                }
            }

            Section("Corrections") {
                if !viewModel.settings.transcriptionCorrections.isEmpty {
                    correctionSearchField
                }

                if viewModel.settings.transcriptionCorrections.isEmpty {
                    Text("Add exact local replacements for phrases Whisper consistently hears wrong, such as chat gp t -> ChatGPT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if visibleCorrectionIndices.isEmpty {
                    Text("No correction rules match this search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(visibleCorrectionIndices, id: \.self) { index in
                    let rowSearchMatches = correctionSearchMatches(for: index)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Heard phrase", text: correctionSourceBinding(index))
                                .focused($focusedCorrectionField, equals: .source(index))
                            Button {
                                removeCorrectionItem(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }

                        TextField("Replace with", text: correctionReplacementBinding(index))
                            .focused($focusedCorrectionField, equals: .replacement(index))

                        if !rowSearchMatches.isEmpty {
                            CorrectionSearchMatchView(
                                matches: Array(rowSearchMatches.prefix(2)),
                                overflowCount: max(0, rowSearchMatches.count - 2)
                            )
                        }

                        Text("Use exact local fixes for phrases that consistently come out wrong before glossary and preset formatting run.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button("Add Correction Rule") {
                    correctionSearchText = ""
                    var corrections = viewModel.settings.transcriptionCorrections
                    corrections.append(
                        TranscriptionCorrectionRule(
                            source: "",
                            replacement: ""
                        )
                    )
                    viewModel.settings.transcriptionCorrections = corrections
                }
            }

            Section("Candidate Corrections") {
                if viewModel.settings.transcriptionCandidateCorrections.isEmpty {
                    Text("Add confidence-gated local replacements for mixed-language phrases Whisper gets close to but not consistently enough for an always-on exact correction. Add source aliases when the same term is misheard in multiple ways.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.settings.transcriptionCandidateCorrections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Heard phrase", text: candidateCorrectionSourceBinding(index))
                            Button {
                                removeCandidateCorrectionItem(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }

                        TextField("Source aliases (comma separated)", text: candidateCorrectionAliasesBinding(index))
                        TextField("Replace with", text: candidateCorrectionReplacementBinding(index))
                        TextField("Evidence note (optional)", text: candidateCorrectionEvidenceDetailBinding(index))

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

                            Slider(value: candidateCorrectionConfidenceBinding(index), in: 0...1, step: 0.05)
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

                                Slider(value: candidateCorrectionMinimumConfidenceBinding(index), in: 0...1, step: 0.05)
                            }
                        }

                        Text("Candidate rules also match common separator variants and conservative Korean/Japanese particle attachments. Low-confidence candidates stay visible to the processor but will not auto-apply.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button("Add Candidate Rule") {
                    var candidateCorrections = viewModel.settings.transcriptionCandidateCorrections
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
                    viewModel.settings.transcriptionCandidateCorrections = candidateCorrections
                }
            }
        }
        .formStyle(.grouped)
    }

    private var glossarySearchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search glossary", text: $glossarySearchText)
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

    private var visibleGlossaryIndices: [Int] {
        let indices = Array(viewModel.settings.transcriptionGlossary.indices)
        let query = glossarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return indices
        }

        return indices.filter { index in
            if focusedGlossaryField?.index == index {
                return true
            }
            return viewModel.settings.transcriptionGlossary[index].matchesSearchQuery(query)
        }
    }

    private var correctionSearchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search corrections", text: $correctionSearchText)
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

    private var visibleCorrectionIndices: [Int] {
        let indices = Array(viewModel.settings.transcriptionCorrections.indices)
        let query = correctionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return indices
        }

        return indices.filter { index in
            if focusedCorrectionField?.index == index {
                return true
            }
            return viewModel.settings.transcriptionCorrections[index].matchesSearchQuery(query)
        }
    }

    private func glossaryBinding(_ index: Int) -> Binding<TranscriptionGlossaryItem> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
                    return TranscriptionGlossaryItem(phrase: "", replacement: "", aliases: [])
                }
                return viewModel.settings.transcriptionGlossary[index]
            },
            set: { updated in
                guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
                    return
                }
                var glossary = viewModel.settings.transcriptionGlossary
                glossary[index] = updated
                viewModel.settings.transcriptionGlossary = glossary
            }
        )
    }

    private func aliasBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionGlossary[index].aliases.joined(separator: ", ")
            },
            set: { updated in
                guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
                    return
                }
                var glossary = viewModel.settings.transcriptionGlossary
                glossary[index].aliases = updated
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                viewModel.settings.transcriptionGlossary = glossary
            }
        )
    }

    private func removeGlossaryItem(at index: Int) {
        guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
            return
        }
        var glossary = viewModel.settings.transcriptionGlossary
        glossary.remove(at: index)
        viewModel.settings.transcriptionGlossary = glossary
    }

    private func correctionSourceBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCorrections[index].source
            },
            set: { updated in
                guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCorrections
                corrections[index].source = updated
                viewModel.settings.transcriptionCorrections = corrections
            }
        )
    }

    private func correctionReplacementBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCorrections[index].replacement
            },
            set: { updated in
                guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCorrections
                corrections[index].replacement = updated
                viewModel.settings.transcriptionCorrections = corrections
            }
        )
    }

    private func removeCorrectionItem(at index: Int) {
        guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
            return
        }
        var corrections = viewModel.settings.transcriptionCorrections
        corrections.remove(at: index)
        viewModel.settings.transcriptionCorrections = corrections
    }

    private func candidateCorrectionSourceBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].source
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].source = updated
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionReplacementBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].replacement
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].replacement = updated
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionAliasesBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].aliases.joined(separator: ", ")
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].aliases = parseCandidateAliases(from: updated)
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionEvidenceDetailBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].evidence.detail ?? ""
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].evidence = TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: updated
                )
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionConfidenceBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return 0
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].confidence
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].confidence = updated
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionAutoApplyStrategyBinding(
        _ index: Int
    ) -> Binding<TranscriptionCandidateAutoApplyPolicy.Strategy> {
        Binding(
            get: { candidateCorrectionAutoApplyStrategy(for: index) },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                let existingThreshold = corrections[index].autoApplyPolicy.minimumConfidence
                    ?? corrections[index].confidence

                switch updated {
                case .never:
                    corrections[index].autoApplyPolicy = .never
                case .always:
                    corrections[index].autoApplyPolicy = .always
                case .ifConfidenceAtLeast:
                    corrections[index].autoApplyPolicy = .ifConfidenceAtLeast(existingThreshold)
                }

                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionMinimumConfidenceBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return 1
                }
                return viewModel.settings.transcriptionCandidateCorrections[index].autoApplyPolicy.minimumConfidence
                    ?? viewModel.settings.transcriptionCandidateCorrections[index].confidence
            },
            set: { updated in
                guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
                    return
                }
                var corrections = viewModel.settings.transcriptionCandidateCorrections
                corrections[index].autoApplyPolicy = .ifConfidenceAtLeast(updated)
                viewModel.settings.transcriptionCandidateCorrections = corrections
            }
        )
    }

    private func candidateCorrectionAutoApplyStrategy(
        for index: Int
    ) -> TranscriptionCandidateAutoApplyPolicy.Strategy {
        guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
            return .never
        }
        return viewModel.settings.transcriptionCandidateCorrections[index].autoApplyPolicy.strategy
    }

    private func candidateCorrectionConfidenceLabel(_ index: Int) -> String {
        guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
            return "0%"
        }
        return viewModel.settings.transcriptionCandidateCorrections[index].confidence.formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    private func candidateCorrectionThresholdLabel(_ index: Int) -> String {
        guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
            return "100%"
        }
        let threshold = viewModel.settings.transcriptionCandidateCorrections[index].autoApplyPolicy.minimumConfidence
            ?? viewModel.settings.transcriptionCandidateCorrections[index].confidence
        return threshold.formatted(.percent.precision(.fractionLength(0)))
    }

    private func parseCandidateAliases(from value: String) -> [String] {
        value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func removeCandidateCorrectionItem(at index: Int) {
        guard viewModel.settings.transcriptionCandidateCorrections.indices.contains(index) else {
            return
        }
        var corrections = viewModel.settings.transcriptionCandidateCorrections
        corrections.remove(at: index)
        viewModel.settings.transcriptionCandidateCorrections = corrections
    }

    private func correctionSearchMatches(for index: Int) -> [TranscriptionCorrectionSearchMatch] {
        guard viewModel.settings.transcriptionCorrections.indices.contains(index) else {
            return []
        }

        let query = correctionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return viewModel.settings.transcriptionCorrections[index].searchMatches(for: query)
    }

    private func suggestedAliasPreview(for index: Int) -> TranscriptionGlossaryAliasSuggestionPreview {
        guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
            return TranscriptionGlossaryAliasSuggestionPreview(visibleAliases: [], overflowCount: 0)
        }
        return viewModel.settings.transcriptionGlossary[index].aliasSuggestionPreview(limit: 3)
    }

    private func searchMatches(for index: Int) -> [TranscriptionGlossarySearchMatch] {
        guard viewModel.settings.transcriptionGlossary.indices.contains(index) else {
            return []
        }

        let query = glossarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return viewModel.settings.transcriptionGlossary[index].searchMatches(for: query)
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

// MARK: - Shortcut Recorder

private struct ShortcutRecorderView: View {
    let displayText: String
    let onShortcutCaptured: (_ keyCode: UInt32, _ modifiers: UInt32) -> Void
    @State private var isRecording = false
    @State private var localKeyMonitor: Any?
    @State private var globalKeyMonitor: Any?
    @State private var captureMessage: String?

    var body: some View {
        Button {
            if isRecording {
                stopMonitoring()
            } else {
                startMonitoring()
            }
        } label: {
            if isRecording {
                Text(captureMessage ?? "Press shortcut... (⌘/⌥/^/⇧ + key)")
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Text(displayText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        captureMessage = nil
        isRecording = true

        // Ensure the app remains active while capturing a shortcut.
        NSApp.activate(ignoringOtherApps: true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleShortcutEvent(event) {
                return nil
            }
            return event
        }

        // Fallback path when local monitoring misses events.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async {
                _ = handleShortcutEvent(event)
            }
        }
    }

    private func stopMonitoring() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        isRecording = false
        captureMessage = nil
    }

    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        let carbonModifiers = nsEventModifiersToCarbonModifiers(event.modifierFlags)
        guard carbonModifiers != 0 else {
            captureMessage = "Press shortcut... (modifier required)"
            return false
        }

        let keyCode = UInt32(event.keyCode)
        onShortcutCaptured(keyCode, carbonModifiers)
        stopMonitoring()
        return true
    }
}

private func nsEventModifiersToCarbonModifiers(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
    let relevant = modifiers.intersection([.command, .option, .control, .shift])
    var result: UInt32 = 0
    if relevant.contains(.command) { result |= UInt32(cmdKey) }
    if relevant.contains(.option) { result |= UInt32(optionKey) }
    if relevant.contains(.control) { result |= UInt32(controlKey) }
    if relevant.contains(.shift) { result |= UInt32(shiftKey) }
    return result
}

// MARK: - Model Tab

private struct ModelTab: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Current Model") {
                HStack {
                    Text(viewModel.settings.selectedModel)
                        .font(.headline)
                    Spacer()
                    Text(viewModel.modelManager.modelSize(variant: viewModel.settings.selectedModel))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Available Models") {
                if viewModel.modelManager.isLargeModelWarningNeeded {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Your Mac has 8GB RAM. Large models may cause memory pressure.")
                            .font(.caption)
                    }
                }

                ForEach(viewModel.modelManager.availableModels) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                                .font(.body)
                            Text(model.sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if model.variant == viewModel.settings.selectedModel {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        if model.isDownloaded {
                            if model.variant != viewModel.settings.selectedModel {
                                Button("Use") {
                                    Task { await viewModel.switchModel(to: model.variant) }
                                }

                                Button("Delete") {
                                    try? viewModel.modelManager.deleteModel(variant: model.variant)
                                }
                                .foregroundStyle(.red)
                            }
                        } else {
                            if viewModel.modelManager.isDownloading && viewModel.modelManager.downloadingModel == model.variant {
                                VStack(alignment: .trailing, spacing: 4) {
                                    HStack(spacing: 8) {
                                        ProgressView(value: viewModel.modelManager.downloadProgressClamped)
                                            .frame(width: 100)
                                        Text(viewModel.modelManager.downloadProgressPercentText)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Downloading...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Download") {
                                    Task {
                                        try? await viewModel.modelManager.downloadModel(variant: model.variant)
                                    }
                                }
                                .disabled(viewModel.modelManager.isDownloading)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, !shortVersion.isEmpty {
            if let buildVersion, !buildVersion.isEmpty, buildVersion != shortVersion {
                return "v\(shortVersion) (\(buildVersion))"
            }
            return "v\(shortVersion)"
        }

        if let buildVersion, !buildVersion.isEmpty {
            return "v\(buildVersion)"
        }

        return "v0.1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Voice Input")
                .font(.title)

            Text(appVersionText)
                .foregroundStyle(.secondary)

            Text("Voice-to-text for macOS. Speak naturally and insert text anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 4) {
                Text("Powered by WhisperKit")
                    .font(.caption)
                Text("On-device speech recognition. Your audio never leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
