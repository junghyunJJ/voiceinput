import Testing
@testable import VoiceInputCore

@Suite("Transcription Correction Rule Tests")
struct TranscriptionCorrectionRuleTests {

    @Test func normalizationTrimsWhitespaceAndDropsEmptyValues() {
        let rules = [
            TranscriptionCorrectionRule(source: " chat gp t ", replacement: " ChatGPT "),
            TranscriptionCorrectionRule(source: "   ", replacement: "ignored"),
            TranscriptionCorrectionRule(source: "fig ma", replacement: "   ")
        ]

        #expect(rules.normalizedForPersistence == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])
    }

    @Test func matchesSearchQueryAcrossSourceAndReplacement() {
        let rule = TranscriptionCorrectionRule(
            source: "chat gp t",
            replacement: "ChatGPT"
        )

        #expect(rule.matchesSearchQuery("chat"))
        #expect(rule.matchesSearchQuery("GPT"))
        #expect(rule.matchesSearchQuery("chatgpt"))
        #expect(!rule.matchesSearchQuery("anthropic"))
    }

    @Test func emptySearchQueryMatchesAllCorrectionRules() {
        let rule = TranscriptionCorrectionRule(
            source: "fig ma",
            replacement: "Figma"
        )

        #expect(rule.matchesSearchQuery(""))
        #expect(rule.matchesSearchQuery("   "))
        #expect(rule.searchMatches(for: "").isEmpty)
    }

    @Test func searchMatchesCaptureSourceAndReplacementHighlights() {
        let rule = TranscriptionCorrectionRule(
            source: "chat gp t",
            replacement: "ChatGPT"
        )

        #expect(
            rule.searchMatches(for: "gp") == [
                TranscriptionCorrectionSearchMatch(
                    source: .source,
                    value: "chat gp t",
                    highlight: TranscriptionCorrectionSearchHighlight(location: 5, length: 2)
                ),
                TranscriptionCorrectionSearchMatch(
                    source: .replacement,
                    value: "ChatGPT",
                    highlight: TranscriptionCorrectionSearchHighlight(location: 4, length: 2)
                )
            ]
        )
    }
}
