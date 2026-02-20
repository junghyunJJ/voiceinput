import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.recordingState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Record / Stop button
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

            Divider()

            // Last transcription
            if !viewModel.lastTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcription:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.lastTranscription)
                        .font(.caption)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Button("Copy Last Transcription") {
                viewModel.copyLastTranscription()
            }
            .keyboardShortcut(
                viewModel.settings.copyActionShortcut.keyEquivalent,
                modifiers: viewModel.settings.copyActionShortcut.eventModifiers
            )
            .disabled(viewModel.lastTranscription.isEmpty)

            Divider()

            // Model status & download
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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

            // Language
            Menu("Language: \(viewModel.settings.selectedLanguage.displayName)") {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Button(lang.displayName) {
                        viewModel.settings.selectedLanguage = lang
                    }
                }
            }

            // Settings
            Button("Settings...") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Quit
            Button("Quit Voice Input") {
                viewModel.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
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
