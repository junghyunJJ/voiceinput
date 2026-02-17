import Foundation

private func log(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] [InsertionMgr] \(message)\n"
    let logURL = URL(fileURLWithPath: "/tmp/voiceinput-debug.log")
    if let data = msg.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: logURL)
        }
    }
}

/// Orchestrates 3-tier text insertion fallback:
/// Tier 1: Accessibility API (AXUIElement) — most reliable for native apps
/// Tier 2: CGEvent keyboard simulation — for short, any-language text
/// Tier 3: Clipboard paste (Cmd+V) — universal fallback
struct TextInsertionManager {
    private let accessibilityInserter = AccessibilityInserter()
    private let keyboardSimulator = KeyboardSimulator()
    private let clipboardInserter = ClipboardInserter()

    enum InsertionMethod: String {
        case accessibility
        case keyboard
        case clipboard
    }

    struct InsertionResult {
        let success: Bool
        let method: InsertionMethod
    }

    /// Insert text at the current cursor position using the best available method.
    func insert(_ text: String, accessibilityAvailable: Bool = false) -> InsertionResult {
        guard !text.isEmpty else {
            return InsertionResult(success: true, method: .accessibility)
        }

        log("insert() called: length=\(text.count), accessibilityAvailable=\(accessibilityAvailable)")

        if accessibilityAvailable {
            // Tier 1: Try Accessibility API
            log("Tier 1: attempting AccessibilityInserter...")
            if accessibilityInserter.insert(text) {
                log("Tier 1: SUCCESS (accessibility)")
                return InsertionResult(success: true, method: .accessibility)
            }
            log("Tier 1: FAILED, falling through to Tier 2")

            // Tier 2: Try CGEvent keyboard simulation (short text, any language)
            let isShort = text.count <= Constants.Transcription.maxCharactersForKeyboardSimulation

            if isShort {
                log("Tier 2: attempting KeyboardSimulator (length=\(text.count))...")
                if keyboardSimulator.insert(text) {
                    log("Tier 2: SUCCESS (keyboard)")
                    return InsertionResult(success: true, method: .keyboard)
                }
                log("Tier 2: FAILED, falling through to Tier 3")
            } else {
                log("Tier 2: SKIPPED (text too long: \(text.count) > \(Constants.Transcription.maxCharactersForKeyboardSimulation))")
            }
        } else {
            log("Tier 1+2: SKIPPED (accessibility not available)")
        }

        // Tier 3: Clipboard paste with AppleScript Cmd+V (works without Accessibility)
        log("Tier 3: attempting ClipboardInserter...")
        let pasteSuccess = clipboardInserter.insert(text)
        log("Tier 3: \(pasteSuccess ? "SUCCESS" : "FAILED") (clipboard)")
        return InsertionResult(success: pasteSuccess, method: .clipboard)
    }
}
