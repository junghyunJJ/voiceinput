import SwiftUI

@main
struct VoiceInputiOSQAApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        let configuration = IOSQALaunchConfiguration.resolve(arguments: ProcessInfo.processInfo.arguments)

        switch configuration.route {
        case .gallery, .none:
            IOSQAGalleryView()
                .iosQAReadiness(configuration.readiness)
        case .host(let state):
            IOSQAHostStateScreen(state: state)
                .iosQAReadiness(configuration.readiness)
        case .keyboardGallery:
            IOSQAKeyboardGalleryView()
                .iosQAReadiness(configuration.readiness)
        }
    }
}
