import Foundation

public enum RecordingMode: String, CaseIterable, Codable, Sendable {
    case toggle
    case pushToTalk

    public var displayName: String {
        switch self {
        case .toggle:
            return "Toggle (tap to start/stop)"
        case .pushToTalk:
            return "Push-to-Talk (hold to record)"
        }
    }
}
