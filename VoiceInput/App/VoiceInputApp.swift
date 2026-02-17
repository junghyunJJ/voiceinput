import SwiftUI

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu bar icon and dropdown
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
                .task {
                    if !viewModel.settings.hasCompletedOnboarding {
                        openWindow(id: "onboarding")
                    }
                }
        } label: {
            Image(systemName: viewModel.recordingState.menuBarIconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.recordingState.isRecording ? .red : .primary)
        }

        // Settings window
        Settings {
            SettingsView(viewModel: viewModel)
                .frame(minWidth: 450, minHeight: 350)
        }

        // Onboarding window
        Window("Welcome to Voice Input", id: "onboarding") {
            OnboardingView(viewModel: viewModel)
                .frame(width: 500, height: 450)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
