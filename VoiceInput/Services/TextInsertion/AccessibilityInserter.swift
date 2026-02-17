import ApplicationServices
import Foundation

private func log(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] [AXInserter] \(message)\n"
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

/// Tier 1: Insert text via Accessibility API (AXUIElement).
/// Most reliable method — works with native macOS apps.
/// Requires Accessibility permission.
struct AccessibilityInserter {

    /// Attempt to insert text at the cursor position using the Accessibility API.
    /// Returns true if successful.
    @discardableResult
    func insert(_ text: String) -> Bool {
        guard let focusedElement = getFocusedTextElement() else {
            log("insert(): no focused text element found")
            return false
        }

        // Try setting selected text range first (insert at cursor)
        let result = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if result == .success {
            log("insert(): kAXSelectedTextAttribute succeeded")
            return true
        }
        log("insert(): kAXSelectedTextAttribute failed with error \(result.rawValue)")

        // Fallback: try setting the entire value (append)
        var currentValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard copyResult == .success, let currentText = currentValue as? String else {
            log("insert(): kAXValueAttribute copy failed with error \(copyResult.rawValue)")
            return false
        }

        // Get selected text range to know cursor position
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard rangeResult == .success, let rangeValue = selectedRange else {
            log("insert(): kAXSelectedTextRangeAttribute copy failed with error \(rangeResult.rawValue)")
            return false
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            log("insert(): AXValueGetValue failed for cfRange")
            return false
        }

        let nsString = currentText as NSString
        let newText = nsString.replacingCharacters(
            in: NSRange(location: range.location, length: range.length),
            with: text
        )
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        if setResult == .success {
            log("insert(): kAXValueAttribute replace succeeded")
        } else {
            log("insert(): kAXValueAttribute replace failed with error \(setResult.rawValue)")
        }
        return setResult == .success
    }

    /// Get the focused text element using Accessibility API.
    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard appResult == .success else {
            log("getFocusedTextElement(): kAXFocusedApplicationAttribute failed with error \(appResult.rawValue)")
            return nil
        }

        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard elemResult == .success else {
            log("getFocusedTextElement(): kAXFocusedUIElementAttribute failed with error \(elemResult.rawValue)")
            return nil
        }

        let element = focusedElement as! AXUIElement

        // Verify the element supports text input
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? "(unknown)"
        log("getFocusedTextElement(): found element with role=\(roleString)")

        return element
    }
}
