import Carbon
import Cocoa
import Foundation

/// Persisted shortcut definition: key code + modifier flags.
struct HotkeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Default: Option+Space
    static let `default` = HotkeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("^") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }

    private func keyCodeName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Escape: return "\u{238B}"
        case kVK_Delete: return "\u{232B}"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_R: return "R"
        default:
            // Use UCKeyTranslate for other keys
            if let char = characterForKeyCode(code) {
                return char.uppercased()
            }
            return "Key\(code)"
        }
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

/// Manages global hotkey registration using Carbon's RegisterEventHotKey.
/// Supports toggle (tap) and push-to-talk (hold) modes.
@MainActor
@Observable
final class HotkeyManager {
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var currentShortcut: HotkeyShortcut

    private var isKeyDown = false
    private var isRecording = false
    private var currentMode: HotkeyMode = .toggle
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x564F4943), id: 1) // "VOIC"

    init() {
        // Load saved shortcut or use default
        if let data = UserDefaults.standard.data(forKey: "hotkeyShortcut"),
           let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
            currentShortcut = shortcut
        } else {
            currentShortcut = .default
        }
    }

    /// Register hotkey handlers based on current mode.
    func register(mode: HotkeyMode) {
        currentMode = mode
        unregisterHotkey()
        registerHotkey(shortcut: currentShortcut)
    }

    /// Update the shortcut and re-register.
    func updateShortcut(_ shortcut: HotkeyShortcut) {
        currentShortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "hotkeyShortcut")
        }
        unregisterHotkey()
        registerHotkey(shortcut: shortcut)
    }

    private func registerHotkey(shortcut: HotkeyShortcut) {
        // Convert modifier flags from Carbon to Carbon hotkey format
        var carbonModifiers: UInt32 = 0
        if shortcut.modifiers & UInt32(cmdKey) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifiers & UInt32(controlKey) != 0 { carbonModifiers |= UInt32(controlKey) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { carbonModifiers |= UInt32(shiftKey) }

        // Install event handler for hotkey pressed/released
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let handlerRef = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                let eventKind = GetEventKind(event)
                Task { @MainActor in
                    if eventKind == UInt32(kEventHotKeyPressed) {
                        manager.handleKeyDown()
                    } else if eventKind == UInt32(kEventHotKeyReleased) {
                        manager.handleKeyUp()
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            handlerRef,
            &eventHandler
        )

        // Register the hotkey
        RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func handleKeyDown() {
        switch currentMode {
        case .toggle:
            // Toggle mode: each keyDown toggles recording
            isRecording.toggle()
            if isRecording {
                onRecordingStarted?()
            } else {
                onRecordingStopped?()
            }
        case .pushToTalk:
            guard !isKeyDown else { return }
            isKeyDown = true
            onRecordingStarted?()
        }
    }

    private func handleKeyUp() {
        switch currentMode {
        case .toggle:
            break // Toggle handles everything on keyDown
        case .pushToTalk:
            isKeyDown = false
            onRecordingStopped?()
        }
    }

    /// Reset recording state (call when recording ends externally).
    func resetState() {
        isRecording = false
        isKeyDown = false
    }

}
