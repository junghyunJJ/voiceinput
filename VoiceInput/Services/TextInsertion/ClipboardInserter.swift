import AppKit
import CoreGraphics
import Foundation

/// Tier 3: Insert text via clipboard (NSPasteboard + Cmd+V).
/// Most compatible method — works with virtually all apps.
/// Saves and restores clipboard contents.
struct ClipboardInserter {

    /// Insert text by copying to clipboard and simulating Cmd+V.
    /// Saves and restores the previous clipboard contents.
    /// Returns true if the paste command was posted successfully.
    @discardableResult
    func insert(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let savedItems = savePasteboard(pasteboard)

        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let pasteResult = simulatePaste()

        // Restore clipboard after a short delay to allow paste to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.restorePasteboard(pasteboard, items: savedItems)
        }

        return pasteResult
    }

    /// Simulate Cmd+V key press.
    /// Tries AppleScript (System Events) first, then CGEvent as fallback.
    private func simulatePaste() -> Bool {
        // Try AppleScript approach (uses Automation permission, not Accessibility)
        if simulatePasteViaAppleScript() {
            return true
        }

        // Fallback to CGEvent
        return simulatePasteViaCGEvent()
    }

    /// Use osascript process + System Events to simulate Cmd+V.
    private func simulatePasteViaAppleScript() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Use CGEvent to simulate Cmd+V.
    private func simulatePasteViaCGEvent() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
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
    private func savePasteboard(_ pasteboard: NSPasteboard) -> [(type: NSPasteboard.PasteboardType, data: Data)] {
        var items: [(type: NSPasteboard.PasteboardType, data: Data)] = []

        guard let types = pasteboard.types else { return items }

        for type in types {
            if let data = pasteboard.data(forType: type) {
                items.append((type: type, data: data))
            }
        }

        return items
    }

    /// Restore previously saved pasteboard items.
    private func restorePasteboard(
        _ pasteboard: NSPasteboard,
        items: [(type: NSPasteboard.PasteboardType, data: Data)]
    ) {
        pasteboard.clearContents()
        for item in items {
            pasteboard.setData(item.data, forType: item.type)
        }
    }
}
