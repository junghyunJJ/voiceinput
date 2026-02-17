import Testing
@testable import VoiceInput

@Suite("RecordingState Tests")
struct RecordingStateTests {

    @Test func idleState() {
        let state = RecordingState.idle
        #expect(state.isIdle)
        #expect(!state.isRecording)
        #expect(!state.isProcessing)
        #expect(state.statusText == "Ready")
        #expect(state.menuBarIconName == "mic")
    }

    @Test func recordingState() {
        let state = RecordingState.recording(startTime: Date())
        #expect(!state.isIdle)
        #expect(state.isRecording)
        #expect(!state.isProcessing)
        #expect(state.menuBarIconName == "mic.fill")
    }

    @Test func transcribingState() {
        let state = RecordingState.transcribing
        #expect(!state.isIdle)
        #expect(!state.isRecording)
        #expect(state.isProcessing)
        #expect(state.statusText == "Transcribing...")
        #expect(state.menuBarIconName == "ellipsis.circle")
    }

    @Test func insertingState() {
        let state = RecordingState.inserting(text: "Hello world")
        #expect(!state.isIdle)
        #expect(!state.isRecording)
        #expect(state.isProcessing)
        #expect(state.statusText == "Inserting text...")
        #expect(state.menuBarIconName == "ellipsis.circle")
    }

    @Test func errorState() {
        let state = RecordingState.error(message: "Something went wrong")
        #expect(!state.isIdle)
        #expect(!state.isRecording)
        #expect(!state.isProcessing)
        #expect(state.statusText == "Error: Something went wrong")
        #expect(state.menuBarIconName == "exclamationmark.triangle")
    }

    @Test func equality() {
        #expect(RecordingState.idle == RecordingState.idle)
        #expect(RecordingState.transcribing == RecordingState.transcribing)
        #expect(RecordingState.idle != RecordingState.transcribing)
        #expect(RecordingState.error(message: "a") == RecordingState.error(message: "a"))
        #expect(RecordingState.error(message: "a") != RecordingState.error(message: "b"))
    }
}
