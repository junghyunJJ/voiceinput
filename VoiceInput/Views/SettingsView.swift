import Carbon
import SwiftUI

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
                        shortcut: viewModel.hotkeyManager.currentShortcut,
                        onShortcutChanged: { newShortcut in
                            viewModel.hotkeyManager.updateShortcut(newShortcut)
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

// MARK: - Shortcut Recorder

private struct ShortcutRecorderView: View {
    let shortcut: HotkeyShortcut
    let onShortcutChanged: (HotkeyShortcut) -> Void
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            if isRecording {
                Text("Press shortcut...")
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Text(shortcut.displayString)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .buttonStyle(.plain)
        .onKeyPress(phases: .down) { press in
            guard isRecording else { return .ignored }
            let carbonModifiers = nsEventModifiersToCarbonModifiers(press.modifiers)
            guard carbonModifiers != 0 else { return .ignored } // Require at least one modifier

            let keyCode = keyCodeFromKeyEquivalent(press.key)
            let newShortcut = HotkeyShortcut(keyCode: keyCode, modifiers: carbonModifiers)
            onShortcutChanged(newShortcut)
            isRecording = false
            return .handled
        }
    }

    private func nsEventModifiersToCarbonModifiers(_ modifiers: SwiftUI.EventModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(SwiftUI.EventModifiers.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(SwiftUI.EventModifiers.option) { result |= UInt32(optionKey) }
        if modifiers.contains(SwiftUI.EventModifiers.control) { result |= UInt32(controlKey) }
        if modifiers.contains(SwiftUI.EventModifiers.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func keyCodeFromKeyEquivalent(_ key: KeyEquivalent) -> UInt32 {
        // Map common KeyEquivalent characters to Carbon key codes
        switch key {
        case .space: return UInt32(kVK_Space)
        case .return: return UInt32(kVK_Return)
        case .tab: return UInt32(kVK_Tab)
        case .escape: return UInt32(kVK_Escape)
        case .delete: return UInt32(kVK_Delete)
        default:
            // For letter keys, use ASCII mapping
            let char = String(key.character).lowercased()
            if let ascii = char.first?.asciiValue {
                // Map a-z to Carbon key codes
                let keyMap: [Character: Int] = [
                    "a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F,
                    "h": kVK_ANSI_H, "g": kVK_ANSI_G, "z": kVK_ANSI_Z, "x": kVK_ANSI_X,
                    "c": kVK_ANSI_C, "v": kVK_ANSI_V, "b": kVK_ANSI_B, "q": kVK_ANSI_Q,
                    "w": kVK_ANSI_W, "e": kVK_ANSI_E, "r": kVK_ANSI_R, "y": kVK_ANSI_Y,
                    "t": kVK_ANSI_T, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
                    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
                    "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
                    "o": kVK_ANSI_O, "u": kVK_ANSI_U, "i": kVK_ANSI_I, "p": kVK_ANSI_P,
                    "l": kVK_ANSI_L, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "n": kVK_ANSI_N,
                    "m": kVK_ANSI_M,
                ]
                if let ch = char.first, let code = keyMap[ch] {
                    return UInt32(code)
                }
                return UInt32(ascii)
            }
            return 0
        }
    }
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
                                ProgressView(value: viewModel.modelManager.downloadProgress)
                                    .frame(width: 80)
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
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Voice Input")
                .font(.title)

            Text("v1.0.0")
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
