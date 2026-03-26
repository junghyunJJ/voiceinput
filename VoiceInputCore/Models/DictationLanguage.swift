import Foundation

public enum DictationLanguage: String, CaseIterable, Codable, Sendable {
    case auto = "auto"
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case chinese = "zh"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    public var displayName: String {
        switch self {
        case .auto:
            return "Auto-detect"
        case .english:
            return "English"
        case .korean:
            return "한국어 (Korean)"
        case .japanese:
            return "日本語 (Japanese)"
        case .chinese:
            return "中文 (Chinese)"
        case .spanish:
            return "Español (Spanish)"
        case .french:
            return "Français (French)"
        case .german:
            return "Deutsch (German)"
        }
    }

    public var whisperCode: String? {
        self == .auto ? nil : rawValue
    }
}
