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

    @Test func diagnosticSummaryIncludesRawCleanAndSegmentDetails() {
        let segments = [
            TranscriptionResult.Segment(text: "[BLANK_AUDIO]", start: 0.0, end: 18.6),
            TranscriptionResult.Segment(text: "kept\nline", start: 18.6, end: 19.0),
        ]

        let diagnostics = TranscriptionDiagnostics(
            rawText: "[BLANK_AUDIO]",
            cleanText: "",
            segments: segments
        )

        let summary = diagnostics.logSummary(
            model: "large-v3-v20240930_turbo_632MB",
            requestedLanguage: "ko",
            audioDuration: 18.6
        )

        #expect(summary == "model=large-v3-v20240930_turbo_632MB, requestedLanguage=ko, audioDuration=18.6s, rawText='[BLANK_AUDIO]', cleanText='', segmentCount=2, segmentPreview='[BLANK_AUDIO] | kept\\nline'")
    }
}
