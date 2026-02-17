import Testing
@testable import VoiceInput

@Suite("TranscriptionResult Tests")
struct TranscriptionResultTests {

    @Test func resultCreation() {
        let segments = [
            TranscriptionResult.Segment(text: "Hello", start: 0.0, end: 0.5),
            TranscriptionResult.Segment(text: " world", start: 0.5, end: 1.0),
        ]

        let result = TranscriptionResult(
            text: "Hello world",
            language: "en",
            segments: segments,
            duration: 1.2
        )

        #expect(result.text == "Hello world")
        #expect(result.language == "en")
        #expect(result.segments.count == 2)
        #expect(abs(result.duration - 1.2) < 0.001)
    }

    @Test func segmentTiming() {
        let segment = TranscriptionResult.Segment(text: "test", start: 1.5, end: 2.3)
        #expect(segment.start == 1.5)
        #expect(segment.end == 2.3)
        #expect(segment.text == "test")
    }

    @Test func emptyResult() {
        let result = TranscriptionResult(
            text: "",
            language: "auto",
            segments: [],
            duration: 0
        )

        #expect(result.text.isEmpty)
        #expect(result.segments.isEmpty)
    }
}
