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
    struct RepairContext {
        fileprivate let targetAppPID: pid_t
        fileprivate let targetElement: AXUIElement
        fileprivate let containerText: String
        fileprivate let insertedRange: NSRange
        fileprivate let originalText: String
    }

    struct Result {
        let success: Bool
        let repairContext: RepairContext?

        init(success: Bool, repairContext: RepairContext? = nil) {
            self.success = success
            self.repairContext = repairContext
        }
    }

    /// Attempt to insert text at the cursor position using the Accessibility API.
    /// Returns true if successful.
    @discardableResult
    func insert(_ text: String) -> Result {
        guard let focusedTarget = getFocusedTextTarget() else {
            log("insert(): no focused text element found")
            return Result(success: false)
        }
        let beforeSnapshot = snapshot(of: focusedTarget.element)

        // Try setting selected text range first (insert at cursor)
        let result = AXUIElementSetAttributeValue(
            focusedTarget.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if result == .success {
            log("insert(): kAXSelectedTextAttribute succeeded")
            return Result(
                success: true,
                repairContext: buildRepairContext(
                    insertedText: text,
                    target: focusedTarget,
                    beforeSnapshot: beforeSnapshot
                )
            )
        }
        log("insert(): kAXSelectedTextAttribute failed with error \(result.rawValue)")

        guard let snapshot = beforeSnapshot else {
            log("insert(): unable to capture text snapshot for fallback replace")
            return Result(success: false)
        }
        return replaceSelection(
            in: focusedTarget,
            snapshot: snapshot,
            with: text
        )
    }

    func repair(_ updatedText: String, using context: RepairContext) -> Result {
        guard !updatedText.isEmpty else {
            return Result(success: false)
        }

        var currentPID: pid_t = 0
        let pidResult = AXUIElementGetPid(context.targetElement, &currentPID)
        guard pidResult == .success, currentPID == context.targetAppPID else {
            log("repair(): target element PID mismatch or unavailable")
            return Result(success: false)
        }

        guard let currentSnapshot = snapshot(of: context.targetElement) else {
            log("repair(): unable to read current text snapshot")
            return Result(success: false)
        }

        guard currentSnapshot.text == context.containerText else {
            log("repair(): container text changed since insertion")
            return Result(success: false)
        }

        let currentNSString = currentSnapshot.text as NSString
        guard NSMaxRange(context.insertedRange) <= currentNSString.length else {
            log("repair(): stored inserted range is out of bounds")
            return Result(success: false)
        }

        let currentInsertedText = currentNSString.substring(with: context.insertedRange)
        guard currentInsertedText == context.originalText else {
            log("repair(): stored inserted range no longer matches original text")
            return Result(success: false)
        }

        let repairedText = currentNSString.replacingCharacters(
            in: context.insertedRange,
            with: updatedText
        )
        let setResult = AXUIElementSetAttributeValue(
            context.targetElement,
            kAXValueAttribute as CFString,
            repairedText as CFTypeRef
        )
        guard setResult == .success else {
            log("repair(): kAXValueAttribute replace failed with error \(setResult.rawValue)")
            return Result(success: false)
        }

        let updatedRange = NSRange(
            location: context.insertedRange.location,
            length: (updatedText as NSString).length
        )
        setSelectedRange(
            updatedRange,
            on: context.targetElement,
            collapseToEnd: true
        )

        return Result(
            success: true,
            repairContext: RepairContext(
                targetAppPID: context.targetAppPID,
                targetElement: context.targetElement,
                containerText: repairedText,
                insertedRange: updatedRange,
                originalText: updatedText
            )
        )
    }

    /// Get the focused text element using Accessibility API.
    private func getFocusedTextTarget() -> FocusedTextTarget? {
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
        let appElement = focusedApp as! AXUIElement

        // Verify the element supports text input
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? "(unknown)"
        log("getFocusedTextElement(): found element with role=\(roleString)")

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(appElement, &pid)
        guard pidResult == .success else {
            log("getFocusedTextElement(): AXUIElementGetPid failed with error \(pidResult.rawValue)")
            return nil
        }

        return FocusedTextTarget(appPID: pid, element: element)
    }

    private func snapshot(of element: AXUIElement) -> TextSnapshot? {
        var currentValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )
        guard copyResult == .success, let currentText = currentValue as? String else {
            log("snapshot(): kAXValueAttribute copy failed with error \(copyResult.rawValue)")
            return nil
        }

        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )
        guard rangeResult == .success, let rangeValue = selectedRangeValue else {
            log("snapshot(): kAXSelectedTextRangeAttribute copy failed with error \(rangeResult.rawValue)")
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            log("snapshot(): AXValueGetValue failed for cfRange")
            return nil
        }

        return TextSnapshot(
            text: currentText,
            selectedRange: NSRange(location: range.location, length: range.length)
        )
    }

    private func replaceSelection(
        in target: FocusedTextTarget,
        snapshot: TextSnapshot,
        with text: String
    ) -> Result {
        let insertedLength = (text as NSString).length
        let newText = (snapshot.text as NSString).replacingCharacters(
            in: snapshot.selectedRange,
            with: text
        )
        let setResult = AXUIElementSetAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )
        guard setResult == .success else {
            log("replaceSelection(): kAXValueAttribute replace failed with error \(setResult.rawValue)")
            return Result(success: false)
        }

        let insertedRange = NSRange(location: snapshot.selectedRange.location, length: insertedLength)
        setSelectedRange(insertedRange, on: target.element, collapseToEnd: true)
        log("replaceSelection(): kAXValueAttribute replace succeeded")

        return Result(
            success: true,
            repairContext: RepairContext(
                targetAppPID: target.appPID,
                targetElement: target.element,
                containerText: newText,
                insertedRange: insertedRange,
                originalText: text
            )
        )
    }

    private func buildRepairContext(
        insertedText: String,
        target: FocusedTextTarget,
        beforeSnapshot: TextSnapshot?
    ) -> RepairContext? {
        let insertedLength = (insertedText as NSString).length
        guard let afterSnapshot = snapshot(of: target.element) else {
            return nil
        }

        if let beforeSnapshot {
            let expectedText = (beforeSnapshot.text as NSString).replacingCharacters(
                in: beforeSnapshot.selectedRange,
                with: insertedText
            )
            let expectedRange = NSRange(location: beforeSnapshot.selectedRange.location, length: insertedLength)
            if afterSnapshot.text == expectedText,
               NSMaxRange(expectedRange) <= (afterSnapshot.text as NSString).length {
                return RepairContext(
                    targetAppPID: target.appPID,
                    targetElement: target.element,
                    containerText: afterSnapshot.text,
                    insertedRange: expectedRange,
                    originalText: insertedText
                )
            }
        }

        let caretLocation = afterSnapshot.selectedRange.location
        let afterNSString = afterSnapshot.text as NSString
        guard afterSnapshot.selectedRange.length == 0,
              caretLocation >= insertedLength else {
            return nil
        }

        let inferredRange = NSRange(location: caretLocation - insertedLength, length: insertedLength)
        guard NSMaxRange(inferredRange) <= afterNSString.length,
              afterNSString.substring(with: inferredRange) == insertedText else {
            return nil
        }

        return RepairContext(
            targetAppPID: target.appPID,
            targetElement: target.element,
            containerText: afterSnapshot.text,
            insertedRange: inferredRange,
            originalText: insertedText
        )
    }

    private func setSelectedRange(
        _ range: NSRange,
        on element: AXUIElement,
        collapseToEnd: Bool
    ) {
        var effectiveRange: CFRange
        if collapseToEnd {
            effectiveRange = CFRange(location: range.location + range.length, length: 0)
        } else {
            effectiveRange = CFRange(location: range.location, length: range.length)
        }

        guard let value = AXValueCreate(.cfRange, &effectiveRange) else {
            log("setSelectedRange(): AXValueCreate failed")
            return
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
        if result != AXError.success {
            log("setSelectedRange(): failed with error \(result.rawValue)")
        }
    }

    private struct FocusedTextTarget {
        let appPID: pid_t
        let element: AXUIElement
    }

    private struct TextSnapshot {
        let text: String
        let selectedRange: NSRange
    }
}
