import Foundation

public struct DictationSessionStateMachine: Sendable {
    public private(set) var recordingState: RecordingState

    public init(recordingState: RecordingState = .idle) {
        self.recordingState = recordingState
    }

    @discardableResult
    public mutating func startRecording(startTime: Date = Date()) -> Bool {
        guard recordingState.isIdle else {
            return false
        }
        recordingState = .recording(startTime: startTime)
        return true
    }

    @discardableResult
    public mutating func beginTranscription() -> Bool {
        guard recordingState.isRecording else {
            return false
        }
        recordingState = .transcribing
        return true
    }

    @discardableResult
    public mutating func beginInsertion(text: String) -> Bool {
        guard case .transcribing = recordingState else {
            return false
        }
        recordingState = .inserting(text: text)
        return true
    }

    public mutating func fail(_ message: String) {
        recordingState = .error(message: message)
    }

    public mutating func reset() {
        recordingState = .idle
    }
}
