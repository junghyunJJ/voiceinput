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
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
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
    private enum HotkeyAction: UInt32 {
        case recording = 1
        case copy = 2
    }

    private static let signature = OSType(0x564F4943) // "VOIC"

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onCopyRequested: (() -> Void)?
    var currentShortcut: HotkeyShortcut
    var currentCopyShortcut: CopyActionShortcut = .default

    private var isKeyDown = false
    private var isRecording = false
    private var currentMode: HotkeyMode = .toggle
    private var eventHandler: EventHandlerRef?
    private var hotkeyRefs: [HotkeyAction: EventHotKeyRef] = [:]

    init() {
        // Load saved shortcut or use default
        if let data = UserDefaults.standard.data(forKey: "hotkeyShortcut"),
           let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
            currentShortcut = shortcut
        } else {
            currentShortcut = .default
        }
    }

    /// Register global hotkeys for recording and copy actions.
    func register(mode: HotkeyMode, copyShortcut: CopyActionShortcut) {
        currentMode = mode
        currentCopyShortcut = copyShortcut
        registerHotkeys()
    }

    /// Update the recording shortcut and re-register hotkeys.
    func updateShortcut(_ shortcut: HotkeyShortcut) {
        currentShortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "hotkeyShortcut")
        }
        registerHotkeys()
    }

    /// Update the copy shortcut and re-register hotkeys.
    func updateCopyShortcut(_ shortcut: CopyActionShortcut) {
        currentCopyShortcut = shortcut
        registerHotkeys()
    }

    private func registerHotkeys() {
        unregisterHotkeys()
        installEventHandlerIfNeeded()

        registerHotkey(
            keyCode: currentShortcut.keyCode,
            modifiers: currentShortcut.modifiers,
            action: .recording
        )

        if currentShortcut.keyCode == currentCopyShortcut.keyCode &&
            currentShortcut.modifiers == currentCopyShortcut.modifiers {
            NSLog("[VoiceInput] Copy hotkey conflicts with recording hotkey. Copy hotkey not registered.")
            return
        }

        registerHotkey(
            keyCode: currentCopyShortcut.keyCode,
            modifiers: currentCopyShortcut.modifiers,
            action: .copy
        )
    }

    private func carbonModifiers(from modifiers: UInt32) -> UInt32 {
        // Convert modifier flags from Carbon to Carbon hotkey format
        var carbonModifiers: UInt32 = 0
        if modifiers & UInt32(cmdKey) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if modifiers & UInt32(optionKey) != 0 { carbonModifiers |= UInt32(optionKey) }
        if modifiers & UInt32(controlKey) != 0 { carbonModifiers |= UInt32(controlKey) }
        if modifiers & UInt32(shiftKey) != 0 { carbonModifiers |= UInt32(shiftKey) }
        return carbonModifiers
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

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
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                let eventKind = GetEventKind(event)
                Task { @MainActor in
                    manager.handleHotkeyEvent(eventKind: eventKind, hotkeyID: hotkeyID.id)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            handlerRef,
            &eventHandler
        )
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, action: HotkeyAction) {
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers(from: modifiers),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard status == noErr, let hotkeyRef else {
            NSLog("[VoiceInput] Failed to register hotkey action=\(action.rawValue), status=\(status)")
            return
        }
        hotkeyRefs[action] = hotkeyRef
    }

    private func unregisterHotkeys() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func handleHotkeyEvent(eventKind: UInt32, hotkeyID: UInt32) {
        guard let action = HotkeyAction(rawValue: hotkeyID) else { return }
        switch action {
        case .recording:
            if eventKind == UInt32(kEventHotKeyPressed) {
                handleRecordingKeyDown()
            } else if eventKind == UInt32(kEventHotKeyReleased) {
                handleRecordingKeyUp()
            }
        case .copy:
            if eventKind == UInt32(kEventHotKeyPressed) {
                onCopyRequested?()
            }
        }
    }

    private func handleRecordingKeyDown() {
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

    private func handleRecordingKeyUp() {
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
