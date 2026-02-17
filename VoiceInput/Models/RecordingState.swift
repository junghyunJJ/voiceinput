import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(startTime: Date)
    case transcribing
    case inserting(text: String)
    case error(message: String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isProcessing: Bool {
        switch self {
        case .transcribing, .inserting:
            return true
        default:
            return false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording(let startTime):
            let duration = Date().timeIntervalSince(startTime)
            return String(format: "Recording %.0fs", duration)
        case .transcribing:
            return "Transcribing..."
        case .inserting:
            return "Inserting text..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var menuBarIconName: String {
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
