import Testing

#if DEBUG
@Suite("iOS QA Launch Configuration Tests")
struct IOSQALaunchConfigurationTests {

    @Test func resolvesGalleryRouteWithReadyRequest() {
        let configuration = IOSQALaunchConfiguration.resolve(arguments: [
            "VoiceInputiOS",
            "--qa-gallery",
            "--qa-ready-token", "gallery-token",
        ])

        #expect(configuration.route == .gallery)
        #expect(configuration.readiness?.token == "gallery-token")
        #expect(configuration.readiness?.screenIdentifier == "gallery-home")
    }

    @Test func resolvesKeyboardRouteWithReadyRequest() {
        let configuration = IOSQALaunchConfiguration.resolve(arguments: [
            "VoiceInputiOS",
            "--qa-keyboard-gallery",
            "--qa-ready-token", "keyboard-token",
        ])

        #expect(configuration.route == .keyboardGallery)
        #expect(configuration.readiness?.token == "keyboard-token")
        #expect(configuration.readiness?.screenIdentifier == "keyboard-gallery")
    }

    @Test func resolvesHostRouteWithStateSpecificReadyRequest() {
        let configuration = IOSQALaunchConfiguration.resolve(arguments: [
            "VoiceInputiOS",
            "--qa-host-state", "suggestedFixes",
            "--qa-ready-token", "host-token",
        ])

        #expect(configuration.route == .host(.suggestedFixes))
        #expect(configuration.readiness?.token == "host-token")
        #expect(configuration.readiness?.screenIdentifier == "host-suggestedFixes")
    }

    @Test func omitsReadinessWhenRouteHasNoScreenIdentifier() {
        let configuration = IOSQALaunchConfiguration.resolve(arguments: [
            "VoiceInputiOS",
            "--qa-ready-token", "unused-token",
        ])

        #expect(configuration.route == .none)
        #expect(configuration.readiness == nil)
    }
}
#endif
