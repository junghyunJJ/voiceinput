import Carbon
import Foundation
import SwiftUI

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

struct CopyActionShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Default: Command+Shift+C
    static let `default` = CopyActionShortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        HotkeyShortcut(keyCode: keyCode, modifiers: modifiers).displayString
    }

    var keyEquivalent: KeyEquivalent {
        switch Int(keyCode) {
        case kVK_Space: return .space
        case kVK_Return: return .return
        case kVK_Tab: return .tab
        case kVK_Escape: return .escape
        case kVK_Delete: return .delete
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default:
            if let character = characterForKeyCode(keyCode)?.lowercased().first {
                return KeyEquivalent(character)
            }
            return "c"
        }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        return result
    }

    private func characterForKeyCode(_ keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        return data.withUnsafeBytes { rawPtr -> String? in
            let layoutPtr = rawPtr.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            var deadKeyState: UInt32 = 0
            var actualLength: Int = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &actualLength,
                &chars
            )
            guard status == noErr, actualLength > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: actualLength)
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

    var copyActionShortcut: CopyActionShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(copyActionShortcut) {
                defaults.set(data, forKey: "copyActionShortcut")
            }
        }
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
        if let data = d.data(forKey: "copyActionShortcut"),
           let shortcut = try? JSONDecoder().decode(CopyActionShortcut.self, from: data) {
            self.copyActionShortcut = shortcut
        } else {
            self.copyActionShortcut = .default
        }
    }
}
