import Foundation
import Testing

@Suite("iOS QA Ready Signal Tests")
struct IOSQAReadySignalTests {

    @Test func resolveReturnsTokenWhenLaunchArgumentIsPresent() {
        let configuration = IOSQAReadySignalConfiguration.resolve(
            arguments: ["VoiceInputiOS", "--qa-gallery", "--qa-ready-token", "token-123"]
        )

        #expect(configuration?.token == "token-123")
    }

    @Test func resolveReturnsNilWhenLaunchArgumentIsMissing() {
        let configuration = IOSQAReadySignalConfiguration.resolve(
            arguments: ["VoiceInputiOS", "--qa-gallery"]
        )

        #expect(configuration == nil)
    }

    @Test func writeMarkerPersistsTokenAndRouteIntoDeterministicFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = IOSQAReadySignalConfiguration(token: "token-123")
        try configuration.writeReadyMarker(route: "host-suggestedFixes", cachesDirectory: root)

        let markerURL = root.appendingPathComponent(IOSQAReadySignalConfiguration.markerFilename)
        let contents = try String(contentsOf: markerURL, encoding: .utf8)

        #expect(contents == "token-123\thost-suggestedFixes\n")
    }
}
