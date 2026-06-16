import Testing
@testable import VoiceInput

@Suite("Transcription Retry Policy Tests")
struct TranscriptionRetryPolicyTests {

    @Test func retriesEmptyTextFromNonEmptyAudioWithSegments() {
        let diagnostics = TranscriptionDiagnostics(
            rawText: "",
            cleanText: "",
            segments: [
                TranscriptionResult.Segment(
                    text: "<|startoftranscript|><|ko|><|transcribe|><|0.00|><|endoftext|>",
                    start: 0,
                    end: 2.7,
                    temperature: 0,
                    avgLogprob: -0.80,
                    compressionRatio: 1.0,
                    noSpeechProb: 0.92
                ),
            ]
        )

        #expect(TranscriptionRetryPolicy.shouldRetryEmptyResult(
            audioSampleCount: 43_200,
            sampleRate: 16_000,
            diagnostics: diagnostics
        ))
    }

    @Test func doesNotRetrySuccessfulText() {
        let diagnostics = TranscriptionDiagnostics(
            rawText: "hello",
            cleanText: "hello",
            segments: [
                TranscriptionResult.Segment(text: "hello", start: 0, end: 1),
            ]
        )

        #expect(!TranscriptionRetryPolicy.shouldRetryEmptyResult(
            audioSampleCount: 16_000,
            sampleRate: 16_000,
            diagnostics: diagnostics
        ))
    }

    @Test func doesNotRetryVeryShortAudio() {
        let diagnostics = TranscriptionDiagnostics(
            rawText: "",
            cleanText: "",
            segments: [
                TranscriptionResult.Segment(text: "", start: 0, end: 0.4),
            ]
        )

        #expect(!TranscriptionRetryPolicy.shouldRetryEmptyResult(
            audioSampleCount: 6_400,
            sampleRate: 16_000,
            diagnostics: diagnostics
        ))
    }
}
