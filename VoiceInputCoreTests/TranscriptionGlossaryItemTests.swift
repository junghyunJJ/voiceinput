import Testing
@testable import VoiceInputCore

@Suite("Transcription Glossary Item Tests")
struct TranscriptionGlossaryItemTests {

    @Test func aliasSuggestionPreviewCapsVisibleAliasesAndCountsOverflow() {
        let item = TranscriptionGlossaryItem(
            phrase: "Open AI Research",
            replacement: "Open AI Research"
        )

        let preview = item.aliasSuggestionPreview(limit: 3)

        #expect(preview.visibleAliases == ["open-ai-research", "open.ai.research", "open_ai_research"])
        #expect(preview.overflowCount == 1)
    }

    @Test func aliasSuggestionPreviewExcludesExplicitAliasesAndUsesReplacementSeed() {
        let item = TranscriptionGlossaryItem(
            phrase: "오픈에이아이",
            replacement: "OpenAI",
            aliases: ["open ai"]
        )

        let preview = item.aliasSuggestionPreview(limit: 3)

        #expect(preview.visibleAliases == ["open-ai", "open.ai", "open_ai"])
        #expect(preview.overflowCount == 0)
    }

    @Test func inferredAliasesIncludeLetterSeparatedAndKoreanPhoneticAcronymVariants() {
        let chatGPT = TranscriptionGlossaryItem(
            phrase: "ChatGPT",
            replacement: "ChatGPT"
        )
        let api = TranscriptionGlossaryItem(
            phrase: "API",
            replacement: "API"
        )

        #expect(chatGPT.inferredAliases.contains("chat g p t"))
        #expect(chatGPT.inferredAliases.contains("chat 지피티"))
        #expect(api.inferredAliases.contains("a p i"))
        #expect(api.inferredAliases.contains("에이피아이"))
    }

    @Test func inferredAliasesDoNotAddHybridPhoneticVariantsForShortTrailingAcronyms() {
        let openAI = TranscriptionGlossaryItem(
            phrase: "OpenAI",
            replacement: "OpenAI"
        )

        #expect(!openAI.inferredAliases.contains("open 에이아이"))
    }

    @Test func matchesSearchQueryAcrossPhraseReplacementExplicitAndInferredAliases() {
        let item = TranscriptionGlossaryItem(
            phrase: "오픈에이아이",
            replacement: "OpenAI",
            aliases: ["chat gpt"]
        )

        #expect(item.matchesSearchQuery("오픈에이"))
        #expect(item.matchesSearchQuery("openai"))
        #expect(item.matchesSearchQuery("chat"))
        #expect(item.matchesSearchQuery("open-ai"))
        #expect(!item.matchesSearchQuery("anthropic"))
    }

    @Test func emptySearchQueryMatchesAllGlossaryItems() {
        let item = TranscriptionGlossaryItem(
            phrase: "OpenAI",
            replacement: "OpenAI"
        )

        #expect(item.matchesSearchQuery(""))
        #expect(item.matchesSearchQuery("   "))
    }

    @Test func searchMatchesClassifyPhraseReplacementExplicitAndSuggestedAliasHits() {
        let item = TranscriptionGlossaryItem(
            phrase: "오픈에이아이",
            replacement: "OpenAI",
            aliases: ["chat gpt"]
        )

        #expect(
            item.searchMatches(for: "오픈에이") == [
                TranscriptionGlossarySearchMatch(
                    source: .phrase,
                    value: "오픈에이아이",
                    highlight: TranscriptionGlossarySearchHighlight(location: 0, length: 4)
                )
            ]
        )
        #expect(
            item.searchMatches(for: "openai") == [
                TranscriptionGlossarySearchMatch(
                    source: .replacement,
                    value: "OpenAI",
                    highlight: TranscriptionGlossarySearchHighlight(location: 0, length: 6)
                )
            ]
        )
        #expect(
            item.searchMatches(for: "chat") == [
                TranscriptionGlossarySearchMatch(
                    source: .explicitAlias,
                    value: "chat gpt",
                    highlight: TranscriptionGlossarySearchHighlight(location: 0, length: 4)
                )
            ]
        )
        #expect(
            item.searchMatches(for: "open-ai") == [
                TranscriptionGlossarySearchMatch(
                    source: .suggestedAlias,
                    value: "open-ai",
                    highlight: TranscriptionGlossarySearchHighlight(location: 0, length: 7)
                )
            ]
        )
    }

    @Test func emptySearchQueryProducesNoSearchMatchMetadata() {
        let item = TranscriptionGlossaryItem(
            phrase: "OpenAI",
            replacement: "OpenAI"
        )

        #expect(item.searchMatches(for: "").isEmpty)
        #expect(item.searchMatches(for: "   ").isEmpty)
    }

    @Test func searchMatchesCaptureHighlightRangeInMatchedValue() {
        let item = TranscriptionGlossaryItem(
            phrase: "오픈에이아이",
            replacement: "OpenAI",
            aliases: ["chat gpt"]
        )

        #expect(
            item.searchMatches(for: "gpt") == [
                TranscriptionGlossarySearchMatch(
                    source: .explicitAlias,
                    value: "chat gpt",
                    highlight: TranscriptionGlossarySearchHighlight(location: 5, length: 3)
                )
            ]
        )
        #expect(
            item.searchMatches(for: "open-") == [
                TranscriptionGlossarySearchMatch(
                    source: .suggestedAlias,
                    value: "open-ai",
                    highlight: TranscriptionGlossarySearchHighlight(location: 0, length: 5)
                )
            ]
        )
    }

    @Test func aliasSuggestionPreviewInfersMissingCompactModelNameVariants() {
        let gpt4o = TranscriptionGlossaryItem(
            phrase: "GPT4o",
            replacement: "GPT-4o"
        )
        let a17Pro = TranscriptionGlossaryItem(
            phrase: "A17Pro",
            replacement: "A17 Pro"
        )
        let m3Max = TranscriptionGlossaryItem(
            phrase: "M3Max",
            replacement: "M3 Max"
        )

        #expect(gpt4o.inferredAliases.contains("gpt 4o"))
        #expect(gpt4o.inferredAliases.contains("gpt.4o"))
        #expect(gpt4o.inferredAliases.contains("gpt_4o"))

        #expect(a17Pro.inferredAliases.contains("a17-pro"))
        #expect(a17Pro.inferredAliases.contains("a17.pro"))
        #expect(a17Pro.inferredAliases.contains("a17_pro"))

        #expect(m3Max.inferredAliases.contains("m3-max"))
        #expect(m3Max.inferredAliases.contains("m3.max"))
        #expect(m3Max.inferredAliases.contains("m3_max"))
    }

    @Test func matchesSearchQueryAcrossCompactModelVariants() {
        let gpt4o = TranscriptionGlossaryItem(
            phrase: "GPT4o",
            replacement: "GPT-4o"
        )
        let a17Pro = TranscriptionGlossaryItem(
            phrase: "A17Pro",
            replacement: "A17 Pro"
        )

        #expect(gpt4o.matchesSearchQuery("gpt4o"))
        #expect(gpt4o.matchesSearchQuery("gpt-4o"))
        #expect(gpt4o.matchesSearchQuery("gpt 4o"))
        #expect(a17Pro.matchesSearchQuery("a17pro"))
        #expect(a17Pro.matchesSearchQuery("a17 pro"))
        #expect(a17Pro.matchesSearchQuery("a17-pro"))
    }

    @Test func inferredAliasesIncludeAcronymLetterAndPhoneticVariants() {
        let item = TranscriptionGlossaryItem(
            phrase: "GPT",
            replacement: "GPT"
        )

        #expect(item.inferredAliases.contains("g p t"))
        #expect(item.inferredAliases.contains("g-p-t"))
        #expect(item.inferredAliases.contains("지피티"))
        #expect(item.inferredAliases.contains("ジーピーティー"))
    }

    @Test func inferredAliasesIncludeHybridVariantsForMixedBrandAndAcronymSeeds() {
        let item = TranscriptionGlossaryItem(
            phrase: "ChatGPT",
            replacement: "ChatGPT"
        )

        #expect(item.inferredAliases.contains("chat g p t"))
        #expect(item.inferredAliases.contains("chat 지피티"))
        #expect(item.inferredAliases.contains("chat ジーピーティー"))
    }

    @Test func searchMatchesDoNotFallBackToTruncatedCompactModelFamilies() {
        let gpt4o = TranscriptionGlossaryItem(
            phrase: "GPT4o",
            replacement: "GPT-4o"
        )
        let a17Pro = TranscriptionGlossaryItem(
            phrase: "A17Pro",
            replacement: "A17 Pro"
        )
        let m3Max = TranscriptionGlossaryItem(
            phrase: "M3Max",
            replacement: "M3 Max"
        )

        #expect(!gpt4o.matchesSearchQuery("gpt-4"))
        #expect(!gpt4o.matchesSearchQuery("gpt 4"))
        #expect(!a17Pro.matchesSearchQuery("a17"))
        #expect(!m3Max.matchesSearchQuery("m3"))
    }

    @Test func aliasSuggestionPreviewInfersMissingExpandedCompactQualifierVariants() {
        let m2Ultra = TranscriptionGlossaryItem(
            phrase: "M2Ultra",
            replacement: "M2 Ultra"
        )
        let x1Mini = TranscriptionGlossaryItem(
            phrase: "X1Mini",
            replacement: "X1-Mini"
        )
        let r1Air = TranscriptionGlossaryItem(
            phrase: "R1Air",
            replacement: "R1 Air"
        )

        #expect(m2Ultra.inferredAliases.contains("m2-ultra"))
        #expect(m2Ultra.inferredAliases.contains("m2.ultra"))
        #expect(m2Ultra.inferredAliases.contains("m2_ultra"))
        #expect(x1Mini.inferredAliases.contains("x1 mini"))
        #expect(x1Mini.inferredAliases.contains("x1.mini"))
        #expect(x1Mini.inferredAliases.contains("x1_mini"))
        #expect(r1Air.inferredAliases.contains("r1-air"))
        #expect(r1Air.inferredAliases.contains("r1.air"))
        #expect(r1Air.inferredAliases.contains("r1_air"))
    }

    @Test func inferredAliasesExpandStandaloneAcronymIntoLetterAndPhoneticVariants() {
        let item = TranscriptionGlossaryItem(
            phrase: "API",
            replacement: "API"
        )

        #expect(item.inferredAliases.contains("a p i"))
        #expect(item.inferredAliases.contains("에이피아이"))
        #expect(item.inferredAliases.contains("エーピーアイ"))
    }

    @Test func inferredAliasesExpandMixedBrandAcronymTailIntoHybridVariants() {
        let item = TranscriptionGlossaryItem(
            phrase: "ChatGPT",
            replacement: "ChatGPT"
        )

        #expect(item.inferredAliases.contains("chat g p t"))
        #expect(item.inferredAliases.contains("chat 지피티"))
        #expect(item.inferredAliases.contains("chat ジーピーティー"))
    }

    @Test func matchesSearchQueryAcrossExpandedCompactQualifierVariants() {
        let m2Ultra = TranscriptionGlossaryItem(
            phrase: "M2Ultra",
            replacement: "M2 Ultra"
        )
        let x1Mini = TranscriptionGlossaryItem(
            phrase: "X1Mini",
            replacement: "X1-Mini"
        )
        let r1Air = TranscriptionGlossaryItem(
            phrase: "R1Air",
            replacement: "R1 Air"
        )

        #expect(m2Ultra.matchesSearchQuery("m2ultra"))
        #expect(m2Ultra.matchesSearchQuery("m2 ultra"))
        #expect(m2Ultra.matchesSearchQuery("m2-ultra"))
        #expect(x1Mini.matchesSearchQuery("x1mini"))
        #expect(x1Mini.matchesSearchQuery("x1 mini"))
        #expect(x1Mini.matchesSearchQuery("x1_mini"))
        #expect(r1Air.matchesSearchQuery("r1air"))
        #expect(r1Air.matchesSearchQuery("r1-air"))
        #expect(r1Air.matchesSearchQuery("r1.air"))
    }

    @Test func searchMatchesDoNotFallBackFromExpandedCompactQualifiers() {
        let m2Ultra = TranscriptionGlossaryItem(
            phrase: "M2Ultra",
            replacement: "M2 Ultra"
        )
        let x1Mini = TranscriptionGlossaryItem(
            phrase: "X1Mini",
            replacement: "X1-Mini"
        )
        let r1Air = TranscriptionGlossaryItem(
            phrase: "R1Air",
            replacement: "R1 Air"
        )

        #expect(!m2Ultra.matchesSearchQuery("m2"))
        #expect(!m2Ultra.matchesSearchQuery("ultra"))
        #expect(!m2Ultra.matchesSearchQuery("m2 pro"))
        #expect(!x1Mini.matchesSearchQuery("x1"))
        #expect(!x1Mini.matchesSearchQuery("mini"))
        #expect(!x1Mini.matchesSearchQuery("x1 mini pro"))
        #expect(!r1Air.matchesSearchQuery("r1"))
        #expect(!r1Air.matchesSearchQuery("air"))
        #expect(!r1Air.matchesSearchQuery("r1 air 2"))
    }

    @Test func aliasSuggestionPreviewInfersMissingDottedModelVersionVariants() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7",
            replacement: "Claude-3.7"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2",
            replacement: "Llama 3.2"
        )

        #expect(claude.inferredAliases.contains("claude 3.7"))
        #expect(llama.inferredAliases.contains("llama-3.2"))
    }

    @Test func matchesSearchQueryAcrossDottedModelVersionVariants() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7",
            replacement: "Claude-3.7"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2",
            replacement: "Llama 3.2"
        )

        #expect(claude.matchesSearchQuery("claude3.7"))
        #expect(claude.matchesSearchQuery("claude-3.7"))
        #expect(claude.matchesSearchQuery("claude 3.7"))
        #expect(llama.matchesSearchQuery("llama3.2"))
        #expect(llama.matchesSearchQuery("llama-3.2"))
        #expect(llama.matchesSearchQuery("llama 3.2"))
    }

    @Test func searchMatchesDoNotFallBackToDottedVersionFamiliesOrBareDecimals() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7",
            replacement: "Claude-3.7"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2",
            replacement: "Llama 3.2"
        )

        #expect(!claude.matchesSearchQuery("3.7"))
        #expect(!claude.matchesSearchQuery("claude 3"))
        #expect(!claude.matchesSearchQuery("claude 3 7"))
        #expect(!claude.matchesSearchQuery("claude 3.7 sonnet"))
        #expect(!llama.matchesSearchQuery("3.2"))
        #expect(!llama.matchesSearchQuery("llama 3"))
        #expect(!llama.matchesSearchQuery("llama 3 2"))
    }

    @Test func aliasSuggestionPreviewInfersMissingFullDottedModelVariants() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7Sonnet",
            replacement: "Claude 3.7 Sonnet"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2Instruct",
            replacement: "Llama-3.2-Instruct"
        )

        #expect(claude.inferredAliases.contains("claude-3.7-sonnet"))
        #expect(!claude.inferredAliases.contains("claude 3.7 sonnet"))
        #expect(llama.inferredAliases.contains("llama 3.2 instruct"))
        #expect(!llama.inferredAliases.contains("llama-3.2-instruct"))
    }

    @Test func matchesSearchQueryAcrossFullDottedModelVariants() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7Sonnet",
            replacement: "Claude 3.7 Sonnet"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2Instruct",
            replacement: "Llama-3.2-Instruct"
        )

        #expect(claude.matchesSearchQuery("claude3.7sonnet"))
        #expect(claude.matchesSearchQuery("claude 3.7 sonnet"))
        #expect(claude.matchesSearchQuery("claude-3.7-sonnet"))
        #expect(llama.matchesSearchQuery("llama3.2instruct"))
        #expect(llama.matchesSearchQuery("llama 3.2 instruct"))
        #expect(llama.matchesSearchQuery("llama-3.2-instruct"))
    }

    @Test func searchMatchesDoNotFallBackFromFullDottedModelVariants() {
        let claude = TranscriptionGlossaryItem(
            phrase: "Claude3.7Sonnet",
            replacement: "Claude 3.7 Sonnet"
        )
        let llama = TranscriptionGlossaryItem(
            phrase: "Llama3.2Instruct",
            replacement: "Llama-3.2-Instruct"
        )

        #expect(!claude.matchesSearchQuery("claude 3.7"))
        #expect(!claude.matchesSearchQuery("claude 3"))
        #expect(!claude.matchesSearchQuery("3.7 sonnet"))
        #expect(!claude.matchesSearchQuery("claude 3.7 opus"))
        #expect(!claude.matchesSearchQuery("claude 3.7 sonnet 4"))
        #expect(!llama.matchesSearchQuery("llama 3.2"))
        #expect(!llama.matchesSearchQuery("llama 3"))
        #expect(!llama.matchesSearchQuery("llama 3.2 vision"))
        #expect(!llama.matchesSearchQuery("instruct"))
    }

    @Test func aliasSuggestionPreviewInfersAdditionalFullDottedLabelVariants() {
        let claudeOpus = TranscriptionGlossaryItem(
            phrase: "Claude3.7Opus",
            replacement: "Claude 3.7 Opus"
        )
        let claudeHaiku = TranscriptionGlossaryItem(
            phrase: "Claude3.7Haiku",
            replacement: "Claude-3.7-Haiku"
        )
        let llamaVision = TranscriptionGlossaryItem(
            phrase: "Llama3.2Vision",
            replacement: "Llama 3.2 Vision"
        )
        let llamaTurbo = TranscriptionGlossaryItem(
            phrase: "Llama3.2Turbo",
            replacement: "Llama-3.2-Turbo"
        )

        #expect(claudeOpus.inferredAliases.contains("claude-3.7-opus"))
        #expect(claudeHaiku.inferredAliases.contains("claude 3.7 haiku"))
        #expect(llamaVision.inferredAliases.contains("llama-3.2-vision"))
        #expect(llamaTurbo.inferredAliases.contains("llama 3.2 turbo"))
    }

    @Test func matchesSearchQueryAcrossAdditionalFullDottedLabels() {
        let claudeOpus = TranscriptionGlossaryItem(
            phrase: "Claude3.7Opus",
            replacement: "Claude 3.7 Opus"
        )
        let claudeHaiku = TranscriptionGlossaryItem(
            phrase: "Claude3.7Haiku",
            replacement: "Claude-3.7-Haiku"
        )
        let llamaVision = TranscriptionGlossaryItem(
            phrase: "Llama3.2Vision",
            replacement: "Llama 3.2 Vision"
        )
        let llamaTurbo = TranscriptionGlossaryItem(
            phrase: "Llama3.2Turbo",
            replacement: "Llama-3.2-Turbo"
        )

        #expect(claudeOpus.matchesSearchQuery("claude3.7opus"))
        #expect(claudeOpus.matchesSearchQuery("claude 3.7 opus"))
        #expect(claudeOpus.matchesSearchQuery("claude-3.7-opus"))
        #expect(claudeHaiku.matchesSearchQuery("claude3.7haiku"))
        #expect(claudeHaiku.matchesSearchQuery("claude 3.7 haiku"))
        #expect(claudeHaiku.matchesSearchQuery("claude-3.7-haiku"))
        #expect(llamaVision.matchesSearchQuery("llama3.2vision"))
        #expect(llamaVision.matchesSearchQuery("llama 3.2 vision"))
        #expect(llamaVision.matchesSearchQuery("llama-3.2-vision"))
        #expect(llamaTurbo.matchesSearchQuery("llama3.2turbo"))
        #expect(llamaTurbo.matchesSearchQuery("llama 3.2 turbo"))
        #expect(llamaTurbo.matchesSearchQuery("llama-3.2-turbo"))
    }

    @Test func searchMatchesDoNotCrossFullDottedLabels() {
        let claudeOpus = TranscriptionGlossaryItem(
            phrase: "Claude3.7Opus",
            replacement: "Claude 3.7 Opus"
        )
        let claudeHaiku = TranscriptionGlossaryItem(
            phrase: "Claude3.7Haiku",
            replacement: "Claude-3.7-Haiku"
        )
        let llamaVision = TranscriptionGlossaryItem(
            phrase: "Llama3.2Vision",
            replacement: "Llama 3.2 Vision"
        )
        let llamaTurbo = TranscriptionGlossaryItem(
            phrase: "Llama3.2Turbo",
            replacement: "Llama-3.2-Turbo"
        )

        #expect(!claudeOpus.matchesSearchQuery("claude 3.7"))
        #expect(!claudeOpus.matchesSearchQuery("claude 3.7 sonnet"))
        #expect(!claudeHaiku.matchesSearchQuery("claude 3.7 opus"))
        #expect(!claudeHaiku.matchesSearchQuery("haiku"))
        #expect(!llamaVision.matchesSearchQuery("llama 3.2"))
        #expect(!llamaVision.matchesSearchQuery("llama 3.2 turbo"))
        #expect(!llamaTurbo.matchesSearchQuery("llama 3.2 vision"))
        #expect(!llamaTurbo.matchesSearchQuery("turbo"))
    }
}
