import Testing
@testable import VoiceInput

@Suite("Menu Bar Actions Tests")
struct MenuBarActionsTests {
    @Test func openSettingsRequestsWindowAndActivatesApp() {
        var events: [String] = []

        MenuBarActions.openSettings(
            open: { events.append("open") },
            activate: { events.append("activate") }
        )

        #expect(events == ["open", "activate"])
    }
}
