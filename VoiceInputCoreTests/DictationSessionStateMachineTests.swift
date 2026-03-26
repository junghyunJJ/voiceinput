import Foundation
import Testing
@testable import VoiceInputCore

@Suite("Dictation Session State Machine Tests")
struct DictationSessionStateMachineTests {

    @Test func happyPathTransitions() {
        var machine = DictationSessionStateMachine()
        #expect(machine.recordingState == .idle)

        let started = machine.startRecording(startTime: Date(timeIntervalSince1970: 100))
        #expect(started)
        #expect(machine.recordingState.isRecording)

        let beganTranscription = machine.beginTranscription()
        #expect(beganTranscription)
        #expect(machine.recordingState == .transcribing)

        let beganInsertion = machine.beginInsertion(text: "hello")
        #expect(beganInsertion)
        #expect(machine.recordingState == .inserting(text: "hello"))

        machine.reset()
        #expect(machine.recordingState == .idle)
    }

    @Test func rejectsInvalidTransitionOrder() {
        var machine = DictationSessionStateMachine()

        let transcribeBeforeRecording = machine.beginTranscription()
        #expect(!transcribeBeforeRecording)
        let insertionBeforeRecording = machine.beginInsertion(text: "x")
        #expect(!insertionBeforeRecording)

        _ = machine.startRecording()
        let insertionBeforeTranscribing = machine.beginInsertion(text: "x")
        #expect(!insertionBeforeTranscribing)
    }

    @Test func failureStateCanBeSetFromAnyPoint() {
        var machine = DictationSessionStateMachine()
        machine.fail("mic denied")

        #expect(machine.recordingState == .error(message: "mic denied"))
        #expect(!machine.recordingState.isProcessing)
    }
}
