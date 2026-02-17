import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: AppViewModel
    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    microphoneStep
                case 2:
                    accessibilityStep
                case 3:
                    hotkeyStep
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        viewModel.settings.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Voice Input")
                .font(.title)
                .fontWeight(.bold)

            Text("Speak naturally and insert text anywhere on your Mac. No typing required.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "waveform", text: "On-device speech recognition (private)")
                FeatureRow(icon: "globe", text: "Korean, English, and more languages")
                FeatureRow(icon: "keyboard", text: "Global hotkey from any app")
                FeatureRow(icon: "text.cursor", text: "Auto-inserts text at cursor")
            }
            .padding(.top, 8)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.permissions.microphoneGranted ? "mic.circle.fill" : "mic.slash.circle")
                .font(.system(size: 48))
                .foregroundStyle(viewModel.permissions.microphoneGranted ? .green : .orange)

            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Voice Input needs your microphone to capture speech. Audio is processed entirely on your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if viewModel.permissions.microphoneGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        await viewModel.permissions.requestMicrophonePermission()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.permissions.accessibilityGranted ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(viewModel.permissions.accessibilityGranted ? .green : .orange)

            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Required to insert transcribed text at your cursor position in any app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if viewModel.permissions.accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        viewModel.permissions.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Add Voice Input to: System Settings > Privacy & Security > Accessibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button("Refresh") {
                viewModel.permissions.refreshPermissions()
            }
            .font(.caption)
        }
    }

    private var hotkeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Set Your Hotkey")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a global shortcut to start/stop recording from any app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack {
                Text("Current Shortcut:")
                Text(viewModel.hotkeyManager.currentShortcut.displayString)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.vertical, 8)

            Picker("Mode:", selection: Binding(
                get: { viewModel.settings.hotkeyMode },
                set: { viewModel.updateHotkeyMode($0) }
            )) {
                ForEach(HotkeyMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text("Tip: Option+Space is the default. Change it in Settings if it conflicts with Raycast or Alfred.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }
}
