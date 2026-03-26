import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var viewModel: AppViewModel
    @State private var actionFeedback: String?
    @State private var actionFeedbackClearTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            statusSection
            Divider()
            recordSection

            if !viewModel.lastTranscription.isEmpty {
                Divider()
                lastResultSection
            }

            if !viewModel.suppressedCandidateSuggestions.isEmpty {
                Divider()
                suggestionsSection
            }

            Divider()
            settingsSection

            Divider()
            Button("Quit Voice Input") {
                viewModel.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            actionFeedbackClearTask?.cancel()
        }
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceInput")
                    .font(.caption.weight(.semibold))
                Text(viewModel.recordingState.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let actionFeedback, !actionFeedback.isEmpty {
                    Text(actionFeedback)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Record")

            Button {
                Task {
                    await viewModel.toggleRecording()
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.recordingState.isRecording ? "stop.fill" : "mic.fill")
                    Text(viewModel.recordingState.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                    Text(viewModel.hotkeyManager.currentShortcut.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel.recordingState.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var lastResultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Last Result")

            VStack(alignment: .leading, spacing: 6) {
                Text("Saved output")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text(viewModel.lastTranscription)
                    .font(.caption)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Button("Copy Last Transcription") {
                    viewModel.copyLastTranscription()
                    setActionFeedback("Copied last transcription.")
                }
                .keyboardShortcut(
                    viewModel.settings.copyActionShortcut.keyEquivalent,
                    modifiers: viewModel.settings.copyActionShortcut.eventModifiers
                )
                .disabled(viewModel.lastTranscription.isEmpty)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Suggestions")

            ForEach(Array(viewModel.suppressedCandidateSuggestions.enumerated()), id: \.offset) { index, candidate in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Manual fix")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Confidence \(Int(candidate.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(candidate.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("→ \(candidate.resolvedReplacement)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        suggestionActionButton("Save as Rule") {
                            let didSave = viewModel.saveSuppressedCandidateSuggestionAsRule(at: index)
                            setActionFeedback(didSave ? "Saved as rule." : "Rule already saved.")
                        }
                        .disabled(!viewModel.canSaveSuppressedCandidateSuggestionAsRule(at: index))

                        if viewModel.canRepairSuppressedCandidateSuggestions {
                            suggestionActionButton("Apply to App") {
                                let didApply = viewModel.applySuppressedCandidateSuggestion(at: index)
                                setActionFeedback(didApply ? "Applied to app." : "Could not apply to app.")
                            }
                        } else {
                            suggestionActionButton("Copy Corrected Text") {
                                let didCopy = viewModel.copySuppressedCandidateSuggestion(at: index)
                                setActionFeedback(didCopy ? "Copied corrected text." : "Could not copy corrected text.")
                            }
                            .disabled(!viewModel.canCopySuppressedCandidateSuggestion(at: index))
                        }

                        Spacer()
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            if let repairUnavailableReason = viewModel.suppressedCandidateRepairUnavailableReason {
                Text(repairUnavailableReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Settings")

            if viewModel.modelManager.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading \(viewModel.modelManager.downloadingModelDisplayName)...")
                            .font(.caption)
                        Spacer()
                        Text(viewModel.modelManager.downloadProgressPercentText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: viewModel.modelManager.downloadProgressClamped)
                }
            } else {
                Menu("Model: \(viewModel.settings.selectedModel)") {
                    ForEach(viewModel.modelManager.availableModels) { model in
                        if model.isDownloaded {
                            Button("\(model.displayName) \(model.variant == viewModel.settings.selectedModel ? "(Active)" : "")") {
                                Task { await viewModel.switchModel(to: model.variant) }
                            }
                        } else {
                            Button("Download \(model.displayName) (\(model.sizeDescription))") {
                                Task { try? await viewModel.modelManager.downloadModel(variant: model.variant) }
                            }
                        }
                    }
                }
            }

            Menu("Language: \(viewModel.settings.selectedLanguage.displayName)") {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Button(lang.displayName) {
                        viewModel.settings.selectedLanguage = lang
                    }
                }
            }

            Button("Settings...") {
                MenuBarActions.openSettings(
                    open: openSettings.callAsFunction,
                    activate: NSApp.activate
                )
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
    }

    private func setActionFeedback(_ message: String) {
        actionFeedback = message
        actionFeedbackClearTask?.cancel()
        actionFeedbackClearTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                actionFeedback = nil
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.recordingState {
        case .idle:
            return .gray
        case .recording:
            return .red
        case .transcribing, .inserting:
            return .orange
        case .error:
            return .yellow
        }
    }
}
