import Foundation

protocol KeyboardTextDocumentHelping: AnyObject {
    func insertTextIntoDocument(_ text: String)
    func deleteBackwardInDocument()
    func advanceToNextKeyboardInputMode()
    func openVoiceInputHostApp()
    func documentContextBeforeInputText() -> String?
    func replaceTextBeforeCursor(currentText: String, with replacement: String)
}

final class KeyboardTextDocumentHelperBridge {
    private weak var helper: (any KeyboardTextDocumentHelping)?

    init(helper: any KeyboardTextDocumentHelping) {
        self.helper = helper
    }

    func insertText(_ text: String) {
        helper?.insertTextIntoDocument(text)
    }

    func deleteBackward() {
        helper?.deleteBackwardInDocument()
    }

    func advanceToNextKeyboard() {
        helper?.advanceToNextKeyboardInputMode()
    }

    func openVoiceInputApp() {
        helper?.openVoiceInputHostApp()
    }

    func hasTextBeforeCursor() -> Bool {
        guard let currentText = helper?.documentContextBeforeInputText() else {
            return false
        }

        return !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func transformCurrentDocumentText(_ transform: (String) -> String) -> Bool {
        guard let helper,
              let currentText = helper.documentContextBeforeInputText(),
              !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        let replacement = transform(currentText)
        guard !replacement.isEmpty else {
            return false
        }

        guard replacement != currentText else {
            return true
        }

        helper.replaceTextBeforeCursor(currentText: currentText, with: replacement)
        return true
    }
}
