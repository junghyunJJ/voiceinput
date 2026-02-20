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
