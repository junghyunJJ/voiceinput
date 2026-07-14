import Testing
@testable import VoiceInput

@Suite("WhisperKit Decoding Options Tests")
struct WhisperKitDecodingOptionsTests {
    @Test func configuresTextOnlyBlankSuppressedDecoding() {
        let options = WhisperKitEngine.makeDecodingOptions(language: "ko")

        #expect(options.language == "ko")
        #expect(options.withoutTimestamps)
        #expect(options.suppressBlank)
        #expect(options.noSpeechThreshold == 0.6)
    }

    @Test func leavesLanguageUnsetForAutomaticDetection() {
        let options = WhisperKitEngine.makeDecodingOptions(language: nil)

        #expect(options.language == nil)
        #expect(options.withoutTimestamps)
        #expect(options.suppressBlank)
    }
}
