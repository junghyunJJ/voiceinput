import Testing
@testable import VoiceInput

@MainActor
@Suite("Text Insertion Tests")
struct TextInsertionManagerTests {
    @Test func pastesBeforeTrustingAccessibilitySuccess() async {
        var attempts: [String] = []
        let manager = TextInsertionManager(
            insertViaAccessibility: { _ in
                attempts.append("accessibility")
                return true
            },
            insertViaKeyboard: { _ in
                attempts.append("keyboard")
                return true
            },
            insertViaClipboard: { text in
                attempts.append("paste: \(text)")
                return true
            }
        )

        let result = await manager.insert("자동 붙여넣기", accessibilityAvailable: true)

        #expect(result.success)
        #expect(result.method == .clipboard)
        #expect(attempts == ["paste: 자동 붙여넣기"])
    }

    @Test func fallsBackToAccessibilityWhenPasteCannotBePosted() async {
        var attempts: [String] = []
        let manager = TextInsertionManager(
            insertViaAccessibility: { _ in
                attempts.append("accessibility")
                return true
            },
            insertViaKeyboard: { _ in
                attempts.append("keyboard")
                return true
            },
            insertViaClipboard: { _ in
                attempts.append("paste")
                return false
            }
        )

        let result = await manager.insert("Hello", accessibilityAvailable: true)

        #expect(result.success)
        #expect(result.method == .accessibility)
        #expect(attempts == ["paste", "accessibility"])
    }

    @Test func reportsFailureWhenPasteIsDeniedWithoutAccessibility() async {
        var attempts: [String] = []
        let manager = TextInsertionManager(
            insertViaAccessibility: { _ in
                attempts.append("accessibility")
                return true
            },
            insertViaKeyboard: { _ in
                attempts.append("keyboard")
                return true
            },
            insertViaClipboard: { _ in
                attempts.append("paste")
                return false
            }
        )

        let result = await manager.insert("Hello", accessibilityAvailable: false)

        #expect(!result.success)
        #expect(attempts == ["paste"])
    }
}
