import AppKit
import Testing
@testable import VoiceInput

@MainActor
@Suite("Clipboard Insertion Tests")
struct ClipboardInserterTests {
    @Test func keepsTranscriptionAvailableForDelayedPaste() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous clipboard", forType: .string)
        var pastedText: String?
        let inserter = ClipboardInserter(pasteboard: pasteboard, simulatePaste: {
            // Browser editors may read the pasteboard after the key event is posted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pastedText = pasteboard.string(forType: .string)
            }
            return true
        })

        #expect(await inserter.insert("받아쓴 문장"))
        try await Task.sleep(for: .seconds(1))

        #expect(pastedText == "받아쓴 문장")
        #expect(pasteboard.string(forType: .string) == "Previous clipboard")
    }

    @Test func preservesContentCopiedWhilePasteIsCompleting() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous clipboard", forType: .string)
        let inserter = ClipboardInserter(pasteboard: pasteboard, simulatePaste: {
            pasteboard.clearContents()
            pasteboard.setString("New user copy", forType: .string)
            return true
        })

        #expect(await inserter.insert("Transcription"))
        try await Task.sleep(for: .seconds(1))

        #expect(pasteboard.string(forType: .string) == "New user copy")
    }

    @Test func keepsTranscriptionOnClipboardWhenAutomaticPasteFails() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous clipboard", forType: .string)
        let inserter = ClipboardInserter(pasteboard: pasteboard, simulatePaste: { false })

        #expect(await !inserter.insert("Transcription"))
        try await Task.sleep(for: .seconds(1))

        #expect(pasteboard.string(forType: .string) == "Transcription")
    }

    @Test func restoresAllClipboardItemsAndRepresentations() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("First item", forType: .string)
        first.setString("<b>First item</b>", forType: .html)
        let second = NSPasteboardItem()
        second.setString("Second item", forType: .string)
        pasteboard.writeObjects([first, second])
        let inserter = ClipboardInserter(pasteboard: pasteboard, simulatePaste: { true })

        #expect(await inserter.insert("Transcription"))
        try await Task.sleep(for: .seconds(1))

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "First item")
        #expect(items.first?.string(forType: .html) == "<b>First item</b>")
        #expect(items.last?.string(forType: .string) == "Second item")
    }
}
