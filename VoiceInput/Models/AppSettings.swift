import Foundation

enum HotkeyMode: String, CaseIterable, Identifiable {
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle: return "Toggle (tap to start/stop)"
        case .pushToTalk: return "Push-to-Talk (hold to record)"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case chinese = "zh"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .korean: return "한국어 (Korean)"
        case .japanese: return "日本語 (Japanese)"
        case .chinese: return "中文 (Chinese)"
        case .spanish: return "Español (Spanish)"
        case .french: return "Français (French)"
        case .german: return "Deutsch (German)"
        }
    }
}

/// App settings backed by UserDefaults with @Observable tracking.
/// Using UserDefaults directly (not @AppStorage) so changes propagate
/// through the @Observable observation system to all views.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: "hotkeyMode") }
    }

    var selectedLanguage: TranscriptionLanguage {
        didSet { defaults.set(selectedLanguage.rawValue, forKey: "selectedLanguage") }
    }

    var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: "selectedModel") }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    var showOverlay: Bool {
        didSet { defaults.set(showOverlay, forKey: "showOverlay") }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var autoInsertText: Bool {
        didSet { defaults.set(autoInsertText, forKey: "autoInsertText") }
    }

    private init() {
        // Load persisted values with defaults
        let d = UserDefaults.standard
        self.hotkeyMode = HotkeyMode(rawValue: d.string(forKey: "hotkeyMode") ?? "") ?? .toggle
        self.selectedLanguage = TranscriptionLanguage(rawValue: d.string(forKey: "selectedLanguage") ?? "") ?? .auto
        self.selectedModel = d.string(forKey: "selectedModel") ?? Constants.Transcription.defaultModelVariant
        self.launchAtLogin = d.bool(forKey: "launchAtLogin")
        self.showOverlay = d.object(forKey: "showOverlay") == nil ? true : d.bool(forKey: "showOverlay")
        self.playSound = d.object(forKey: "playSound") == nil ? true : d.bool(forKey: "playSound")
        self.hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        self.autoInsertText = d.object(forKey: "autoInsertText") == nil ? true : d.bool(forKey: "autoInsertText")
    }
}
