import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording(startTime: Date)
    case transcribing
    case inserting(text: String)
    case error(message: String)

    public var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    public var isProcessing: Bool {
        switch self {
        case .transcribing, .inserting:
            return true
        default:
            return false
        }
    }

    public var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    public func statusText(now: Date = Date()) -> String {
        switch self {
        case .idle:
            return "Ready"
        case .recording(let startTime):
            let duration = now.timeIntervalSince(startTime)
            return String(format: "Recording %.0fs", duration)
        case .transcribing:
            return "Transcribing..."
        case .inserting:
            return "Inserting text..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    public var statusSymbolName: String {
        switch self {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .transcribing, .inserting:
            return "ellipsis.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}
