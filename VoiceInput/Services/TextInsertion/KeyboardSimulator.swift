import Carbon
import CoreGraphics
import Foundation

/// Tier 2: Insert text by simulating keyboard events (CGEvent).
/// Works for short text (<200 chars). Korean text may not work reliably.
struct KeyboardSimulator {

    /// Insert text by posting CGEvent key events for each character.
    /// Returns true if events were posted successfully.
    /// - Parameter text: Text to insert (should be <200 chars for reliability).
    @discardableResult
    func insert(_ text: String) -> Bool {
        guard text.count <= Constants.Transcription.maxCharactersForKeyboardSimulation else {
            return false
        }

        for scalar in text.unicodeScalars {
            guard postCharacter(scalar) else {
                return false
            }
            // Small delay between characters for reliability
            usleep(5000) // 5ms
        }

        return true
    }

    /// Post a single Unicode character as a CGEvent key press.
    private func postCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let char = UniChar(scalar.value)
        var charArray = [char]

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            return false
        }
        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &charArray)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &charArray)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}
