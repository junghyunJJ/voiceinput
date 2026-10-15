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

/// Pastes text first so browser editors receive normal paste/input events.
/// Falls back to Accessibility API and short-text keyboard simulation.
@MainActor
struct TextInsertionManager {
    private let insertViaAccessibility: (String) -> Bool
    private let insertViaKeyboard: (String) -> Bool
    private let insertViaClipboard: (String) async -> Bool

    init(
        insertViaAccessibility: @escaping (String) -> Bool = AccessibilityInserter().insert,
        insertViaKeyboard: @escaping (String) -> Bool = KeyboardSimulator().insert,
        insertViaClipboard: @escaping (String) async -> Bool = { await ClipboardInserter().insert($0) }
    ) {
        self.insertViaAccessibility = insertViaAccessibility
        self.insertViaKeyboard = insertViaKeyboard
        self.insertViaClipboard = insertViaClipboard
    }

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
    func insert(_ text: String, accessibilityAvailable: Bool = false) async -> InsertionResult {
        guard !text.isEmpty else {
            return InsertionResult(success: true, method: .accessibility)
        }

        log("insert() called: length=\(text.count), accessibilityAvailable=\(accessibilityAvailable)")

        // AX setters can report success without updating a web editor's input state.
        log("Attempting clipboard paste...")
        if await insertViaClipboard(text) {
            log("SUCCESS (clipboard paste command posted)")
            return InsertionResult(success: true, method: .clipboard)
        }
        log("Clipboard paste unavailable, attempting fallbacks")

        if accessibilityAvailable {
            log("Attempting AccessibilityInserter...")
            if insertViaAccessibility(text) {
                log("SUCCESS (accessibility)")
                return InsertionResult(success: true, method: .accessibility)
            }
            log("Accessibility insertion failed")

            let isShort = text.count <= Constants.Transcription.maxCharactersForKeyboardSimulation

            if isShort {
                log("Attempting KeyboardSimulator (length=\(text.count))...")
                if insertViaKeyboard(text) {
                    log("SUCCESS (keyboard)")
                    return InsertionResult(success: true, method: .keyboard)
                }
                log("Keyboard insertion failed")
            } else {
                log("Keyboard insertion skipped (text too long: \(text.count))")
            }
        } else {
            log("Fallbacks skipped (accessibility not available)")
        }

        return InsertionResult(success: false, method: .clipboard)
    }
}
