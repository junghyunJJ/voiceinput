import AppKit
import CoreGraphics
import Foundation

/// Inserts text via clipboard (NSPasteboard + Cmd+V), preserving prior contents.
@MainActor
struct ClipboardInserter {
    private let pasteboard: NSPasteboard
    private let simulatePasteCommand: (() -> Bool)?

    init(pasteboard: NSPasteboard = .general, simulatePaste: (() -> Bool)? = nil) {
        self.pasteboard = pasteboard
        self.simulatePasteCommand = simulatePaste
    }

    /// Insert text by copying to clipboard and simulating Cmd+V.
    /// Saves and restores the previous clipboard contents.
    /// Returns true if the paste command was posted successfully.
    @discardableResult
    func insert(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }

        // Save current clipboard contents
        let savedItems = savePasteboard(pasteboard)

        // Set new text to clipboard
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        let insertionChangeCount = pasteboard.changeCount

        // Simulate Cmd+V
        guard simulatePasteCommand?() ?? simulatePaste() else {
            // Leave the transcription available for manual paste if posting is denied.
            return false
        }

        // Web editors can read the clipboard asynchronously after the key event.
        do {
            try await Task.sleep(for: .milliseconds(750))
        } catch {
            return true
        }

        // Never overwrite something the user copied while the paste was completing.
        if pasteboard.changeCount == insertionChangeCount {
            restorePasteboard(pasteboard, items: savedItems)
        }

        return true
    }

    /// Simulate Cmd+V key press.
    /// Uses the app's Accessibility permission without a System Events subprocess.
    private func simulatePaste() -> Bool {
        guard CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        // Key code 9 = 'V'
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    /// Save all pasteboard items for later restoration.
    private func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Restore previously saved pasteboard items.
    private func restorePasteboard(
        _ pasteboard: NSPasteboard,
        items: [NSPasteboardItem]
    ) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
