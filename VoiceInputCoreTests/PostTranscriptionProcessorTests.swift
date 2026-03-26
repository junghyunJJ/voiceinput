import Foundation
import Testing
@testable import VoiceInputCore

@Suite("Post Transcription Processor Tests")
struct PostTranscriptionProcessorTests {

    @Test func noOpConfigurationStartsEmptyAndExactPreserving() {
        let configuration = PostTranscriptionProcessingConfiguration.noOp

        #expect(configuration.glossary.isEmpty)
        #expect(configuration.corrections.isEmpty)
        #expect(configuration.formatting == .preserveExactOutput)
        #expect(configuration.isNoOp)
    }

    @Test func processingConfigurationRoundTripsThroughCodable() throws {
        let configuration = PostTranscriptionProcessingConfiguration(
            glossary: [
                TranscriptionGlossaryItem(
                    phrase: "open ai",
                    replacement: "OpenAI",
                    aliases: ["openai"]
                )
            ],
            corrections: [
                TranscriptionCorrectionRule(
                    source: "teh",
                    replacement: "the"
                )
            ],
            formatting: TranscriptionFormattingOptions(
                capitalizeFirstCharacter: true,
                ensureTrailingPunctuation: true,
                trimLeadingAndTrailingWhitespace: true
            ),
            outputPreset: .polishedMessage
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(PostTranscriptionProcessingConfiguration.self, from: data)

        #expect(decoded == configuration)
        #expect(!decoded.isNoOp)
    }

    @Test func noOpProcessorPreservesExactOutput() {
        let original = "  keep  spacing,\nline breaks, and punctuation?!  "
        let processor = PostTranscriptionProcessor(configuration: .noOp)

        let result = processor.process(original)

        #expect(result.originalText == original)
        #expect(result.processedText == original)
        #expect(!result.didChange)
    }

    @Test func glossaryCorrectionsAndPolishedPresetProduceDeterministicOutput() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai", "openai"]
                    )
                ],
                corrections: [
                    TranscriptionCorrectionRule(
                        source: "teh",
                        replacement: "the"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  ping open ai about teh launch update  ")

        #expect(result.processedText == "Ping OpenAI about the launch update.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesHandleMixedLanguageInput() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai", "오픈에이아이"]
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  오픈에이아이 launch note  ")

        #expect(result.processedText == "OpenAI launch note.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesMatchFlexibleSeparatorVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai"]
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  share with open-ai and open.ai and open_ai  ")

        #expect(result.processedText == "Share with OpenAI and OpenAI and OpenAI.")
        #expect(result.didChange)
    }

    @Test func glossaryInfersEnglishSeparatorAliasesFromCanonicalPhrase() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  share with open ai and open-ai and open.ai  ")

        #expect(result.processedText == "Share with OpenAI and OpenAI and OpenAI.")
        #expect(result.didChange)
    }

    @Test func glossaryInfersEnglishAliasesFromReplacementForMixedLanguageCanonicalPhrase() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "오픈에이아이",
                        replacement: "OpenAI"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  sync with open ai before launch  ")

        #expect(result.processedText == "Sync with OpenAI before launch.")
        #expect(result.didChange)
    }

    @Test func glossaryInfersLetterSeparatedAcronymAliasesFromAsciiSeed() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "ChatGPT",
                        replacement: "ChatGPT"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat g p t에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.didChange)
    }

    @Test func glossaryInfersKoreanPhoneticAcronymAliasesFromAsciiSeed() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "ChatGPT",
                        replacement: "ChatGPT"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "API",
                        replacement: "API"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let chatGPTResult = processor.process("chat 지피티에서 확인")
        let apiResult = processor.process("에이피아이 키 확인")

        #expect(chatGPTResult.processedText == "ChatGPT에서 확인")
        #expect(apiResult.processedText == "API 키 확인")
    }

    @Test func glossaryAliasesPreserveAttachedKoreanParticles() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai"]
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  open ai에서 일정 확인하고 open ai는 다음 주에 써요  ")

        #expect(result.processedText == "OpenAI에서 일정 확인하고 OpenAI는 다음 주에 써요.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesPreserveAttachedJapaneseParticles() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai"]
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  open aiで確認して open-aiは来週です  ")

        #expect(result.processedText == "OpenAIで確認して OpenAIは来週です.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesNormalizeHybridAcronymPhoneticVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "ChatGPT",
                        replacement: "ChatGPT"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesNormalizeStandaloneAcronymPhoneticVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "API",
                        replacement: "API"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("에이피아이 명세 확인")

        #expect(result.processedText == "API 명세 확인")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesNormalizeCompactModelVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "GPT4o",
                        replacement: "GPT-4o"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "A17Pro",
                        replacement: "A17 Pro"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "M3Max",
                        replacement: "M3 Max"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  compare gpt 4o with gpt4o on a17-pro and m3 max  ")

        #expect(result.processedText == "Compare GPT-4o with GPT-4o on A17 Pro and M3 Max.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesDoNotMatchTruncatedCompactModelFamilies() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "GPT4o",
                        replacement: "GPT-4o"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "A17Pro",
                        replacement: "A17 Pro"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "M3Max",
                        replacement: "M3 Max"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("gpt-4 on a17 with m3 and claude 3.7")

        #expect(result.processedText == "gpt-4 on a17 with m3 and claude 3.7")
        #expect(!result.didChange)
    }

    @Test func glossaryAliasesNormalizeExpandedCompactQualifiers() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "M2Ultra",
                        replacement: "M2 Ultra"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "X1Mini",
                        replacement: "X1 Mini"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "R1Air",
                        replacement: "R1 Air"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  compare m2-ultra with x1 mini and r1_air  ")

        #expect(result.processedText == "Compare M2 Ultra with X1 Mini and R1 Air.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesDoNotMatchTruncatedOrStackedCompactQualifiers() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "M2Ultra",
                        replacement: "M2 Ultra"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "X1Mini",
                        replacement: "X1 Mini"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "R1Air",
                        replacement: "R1 Air"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("m2 with x1 and r1 and m2 ultra pro and x1 mini max and r1 air 2")

        #expect(result.processedText == "m2 with x1 and r1 and m2 ultra pro and x1 mini max and r1 air 2")
        #expect(!result.didChange)
    }

    @Test func glossaryAliasesNormalizeDottedModelVersionVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7",
                        replacement: "Claude-3.7"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2",
                        replacement: "Llama 3.2"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  compare claude 3.7 with claude3.7 and llama-3.2  ")

        #expect(result.processedText == "Compare Claude-3.7 with Claude-3.7 and Llama 3.2.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesDoNotMatchTruncatedDottedVersionFamilies() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7",
                        replacement: "Claude-3.7"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2",
                        replacement: "Llama 3.2"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("claude 3 with claude 3 7 and claude 3.7 sonnet plus bare 3.7 and llama 3")

        #expect(result.processedText == "claude 3 with claude 3 7 and claude 3.7 sonnet plus bare 3.7 and llama 3")
        #expect(!result.didChange)
    }

    @Test func glossaryAliasesNormalizeFullDottedModelVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Sonnet",
                        replacement: "Claude 3.7 Sonnet"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Instruct",
                        replacement: "Llama 3.2 Instruct"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process(
            "  compare claude 3.7 sonnet with claude-3.7-sonnet and llama3.2instruct에서  "
        )

        #expect(
            result.processedText
                == "Compare Claude 3.7 Sonnet with Claude 3.7 Sonnet and Llama 3.2 Instruct에서."
        )
        #expect(result.didChange)
    }

    @Test func glossaryAliasesDoNotMatchTruncatedOrWrongFullDottedVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Sonnet",
                        replacement: "Claude 3.7 Sonnet"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Instruct",
                        replacement: "Llama 3.2 Instruct"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process(
            "claude 3.7 with claude 3 and claude 3.7 opus and claude 3.7 sonnet 4 and llama 3.2 vision"
        )

        #expect(
            result.processedText
                == "claude 3.7 with claude 3 and claude 3.7 opus and claude 3.7 sonnet 4 and llama 3.2 vision"
        )
        #expect(!result.didChange)
    }

    @Test func longerFullDottedModelVariantWinsWhenBaseVariantAlsoExists() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7",
                        replacement: "Claude-3.7"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Sonnet",
                        replacement: "Claude 3.7 Sonnet"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  compare claude 3.7 sonnet with claude 3.7  ")

        #expect(result.processedText == "Compare Claude 3.7 Sonnet with Claude-3.7.")
        #expect(result.didChange)
    }

    @Test func glossaryAliasesNormalizeAdditionalFullDottedLabels() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Opus",
                        replacement: "Claude 3.7 Opus"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Haiku",
                        replacement: "Claude 3.7 Haiku"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Vision",
                        replacement: "Llama 3.2 Vision"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Turbo",
                        replacement: "Llama 3.2 Turbo"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process(
            "  compare claude-3.7-opus with claude 3.7 haiku and llama3.2vision and llama-3.2-turbo  "
        )

        #expect(
            result.processedText
                == "Compare Claude 3.7 Opus with Claude 3.7 Haiku and Llama 3.2 Vision and Llama 3.2 Turbo."
        )
        #expect(result.didChange)
    }

    @Test func glossaryAliasesDoNotCrossOrStackAdditionalFullDottedLabels() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Opus",
                        replacement: "Claude 3.7 Opus"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Claude3.7Haiku",
                        replacement: "Claude 3.7 Haiku"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Vision",
                        replacement: "Llama 3.2 Vision"
                    ),
                    TranscriptionGlossaryItem(
                        phrase: "Llama3.2Turbo",
                        replacement: "Llama 3.2 Turbo"
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process(
            "claude 3.7 opus max and claude 3.7 haiku sonnet and llama 3.2 vision turbo and llama 3.2 turbo 2"
        )

        #expect(
            result.processedText
                == "claude 3.7 opus max and claude 3.7 haiku sonnet and llama 3.2 vision turbo and llama 3.2 turbo 2"
        )
        #expect(!result.didChange)
    }

    @Test func meetingNotesPresetBuildsBulletList() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                formatting: .preserveExactOutput,
                outputPreset: .meetingNotes
            )
        )

        let result = processor.process("review launch checklist. confirm qa signoff. share update")

        #expect(result.processedText == "- Review launch checklist\n- Confirm qa signoff\n- Share update")
        #expect(result.didChange)
    }

    @Test func highConfidenceCandidateCorrectionsAutoApplyAndEmitEvidence() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "personal mixed-language correction"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  ping chat gp t after lunch  ")

        #expect(result.processedText == "Ping ChatGPT after lunch.")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat gp t")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsMatchFlexibleSeparatorsAndSuffixes() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language separator heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat-gp-t에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat-gp-t에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsMatchAliasVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("챗 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "챗 지피티에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsMatchReplacementInferredSeparatedAcronymVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "replacement inferred acronym heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat g p t에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat g p t에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsMatchReplacementInferredKoreanPhoneticVariants() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "replacement inferred phonetic heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat 지피티에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsMatchInferredReplacementSideAcronymAliases() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "replacement-side acronym phonetic heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat 지피티에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsInferReplacementSideAcronymAliases() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "replacement-side acronym inference"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat 지피티에서")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsDoNotTreatKoreanWordPrefixesAsParticles() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language separator heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat-gp-t에러")

        #expect(result.processedText == "chat-gp-t에러")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func highConfidenceCandidateCorrectionsDoNotTreatJapaneseWordPrefixesAsParticles() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.96,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language separator heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat-gp-tのり")

        #expect(result.processedText == "chat-gp-tのり")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func lowConfidenceCandidateCorrectionsAreSuppressedWithoutRewritingText() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  ping chat gp t after lunch  ")

        #expect(result.processedText == "Ping chat gp t after lunch.")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 1)
        #expect(result.suppressedCandidates.first?.sourceText == "chat gp t")
        #expect(result.suppressedCandidates.first?.resolvedReplacement == "ChatGPT")
    }

    @Test func lowConfidenceCandidateCorrectionsSuppressFlexibleSeparatorMatches() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("챗 지피티에서 확인")

        #expect(result.processedText == "챗 지피티에서 확인")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 1)
        #expect(result.suppressedCandidates.first?.sourceText == "챗 지피티에서")
        #expect(result.suppressedCandidates.first?.resolvedReplacement == "ChatGPT에서")
    }

    @Test func duplicateSuppressedCandidatesCollapseToHighestConfidenceWinner() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.61,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "chat g p t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.74,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "higher confidence overlap"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("챗 지피티에서 확인")

        #expect(result.processedText == "챗 지피티에서 확인")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 1)
        #expect(result.suppressedCandidates.first?.sourceText == "챗 지피티에서")
        #expect(result.suppressedCandidates.first?.resolvedReplacement == "ChatGPT에서")
        #expect(result.suppressedCandidates.first?.confidence == 0.74)
        #expect(result.suppressedCandidates.first?.canonicalSource == nil)
    }

    @Test func overlappingSuppressedCandidatesWithSameReplacementCollapseToOneWinner() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.61,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "full phrase"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.74,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "partial overlap"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat gp t 확인")

        #expect(result.processedText == "chat gp t 확인")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 1)
        #expect(result.suppressedCandidates.first?.sourceText == "chat gp t")
        #expect(result.suppressedCandidates.first?.resolvedReplacement == "ChatGPT")
        #expect(result.suppressedCandidates.first?.confidence == 0.61)
        #expect(result.suppressedCandidates.first?.canonicalSource == nil)
    }

    @Test func overlappingSuppressedCandidatesDoNotBridgeDistinctOccurrences() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.61,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "full phrase"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.74,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "partial overlap"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat gp t 그리고 chat gp t")

        #expect(result.processedText == "chat gp t 그리고 chat gp t")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 2)
        #expect(result.suppressedCandidates.map(\.sourceRangeLocation) == [0, 14])
        #expect(result.suppressedCandidates.allSatisfy { $0.resolvedReplacement == "ChatGPT" })
        #expect(result.suppressedCandidates.allSatisfy { $0.confidence == 0.61 })
        #expect(result.suppressedCandidates.allSatisfy { $0.canonicalSource == nil })
    }

    @Test func chainedPartialOverlapsDoNotCollapseIntoOneRepresentative() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "alpha beta",
                        aliases: [],
                        replacement: "AlphaBeta",
                        confidence: 0.61,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "leading phrase"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "beta gamma",
                        aliases: [],
                        replacement: "AlphaBeta",
                        confidence: 0.73,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "bridge phrase"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "gamma",
                        aliases: [],
                        replacement: "AlphaBeta",
                        confidence: 0.58,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "trailing phrase"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("alpha beta gamma")

        #expect(result.processedText == "alpha beta gamma")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 2)
        #expect(result.suppressedCandidates.map(\.sourceText) == ["alpha beta", "beta gamma"])
        #expect(result.suppressedCandidates.map(\.sourceRangeLocation) == [0, 6])
        #expect(result.suppressedCandidates.allSatisfy { $0.resolvedReplacement == "AlphaBeta" })
    }

    @Test func suppressedCandidatesKeepDistinctReplacementAlternativesForSameSpan() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.66,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "english brand"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "챗GPT",
                        confidence: 0.63,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "hybrid brand"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat gp t 확인")

        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 2)
        #expect(result.suppressedCandidates.map(\.resolvedReplacement) == ["ChatGPT", "챗GPT"])
    }

    @Test func suppressedCandidatesDoNotCollapseDistinctOccurrencesOfSameSourceText() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "ChatGPT",
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "duplicate occurrence safety"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("chat gp t 그리고 chat gp t")

        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.count == 2)
        #expect(result.suppressedCandidates.map(\.sourceRangeLocation) == [0, 14])
        #expect(result.suppressedCandidates.allSatisfy { $0.resolvedReplacement == "ChatGPT" })
    }

    @Test func conflictingCanonicalSourcesClearPromotionProvenanceInsteadOfPickingOneArbitrarily() {
        let sharedEvidence = TranscriptionCorrectionEvidence(
            kind: .candidateRule,
            detail: "shared alias collision"
        )
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.62,
                        evidence: sharedEvidence,
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    ),
                    TranscriptionCandidateCorrectionRule(
                        source: "chat g p t",
                        aliases: ["챗 지피티"],
                        replacement: "ChatGPT",
                        confidence: 0.62,
                        evidence: sharedEvidence,
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("챗 지피티에서 확인")

        #expect(result.suppressedCandidates.count == 1)
        #expect(result.suppressedCandidates.first?.canonicalSource == nil)
        #expect(result.suppressedCandidates.first?.promotedAlwaysApplyRule == TranscriptionCandidateCorrectionRule(
            source: "챗 지피티",
            aliases: [],
            replacement: "ChatGPT",
            confidence: 1,
            evidence: sharedEvidence,
            autoApplyPolicy: .always
        ))
    }

    @Test func explicitCorrectionsTakePrecedenceOverCandidateCorrections() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                corrections: [
                    TranscriptionCorrectionRule(
                        source: "chat gp t",
                        replacement: "ChatGPT"
                    )
                ],
                candidateCorrections: [
                    TranscriptionCandidateCorrectionRule(
                        source: "chat gp t",
                        aliases: [],
                        replacement: "Chat G P T",
                        confidence: 0.99,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "fallback heuristic"
                        ),
                        autoApplyPolicy: .always
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .polishedMessage
            )
        )

        let result = processor.process("  ping chat gp t after lunch  ")

        #expect(result.processedText == "Ping ChatGPT after lunch.")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.sourceText == "chat gp t")
        #expect(result.appliedCorrections.first?.resolvedReplacement == "ChatGPT")
        #expect(result.suppressedCandidates.isEmpty)
    }

    @Test func alreadyNormalizedSuffixMatchesDoNotEmitAppliedCorrections() {
        let processor = PostTranscriptionProcessor(
            configuration: PostTranscriptionProcessingConfiguration(
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai"]
                    )
                ],
                formatting: .preserveExactOutput,
                outputPreset: .verbatim
            )
        )

        let result = processor.process("OpenAI에서 확인")

        #expect(result.processedText == "OpenAI에서 확인")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.isEmpty)
    }
}
