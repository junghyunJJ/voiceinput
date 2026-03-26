import Foundation
import Testing
@testable import VoiceInputCore

@Suite("Transcription Candidate Correction Rule Tests")
struct TranscriptionCandidateCorrectionRuleTests {

    @Test func normalizationTrimsAliasesDedupesAndDropsSourceDuplicates() {
        let rules = [
            TranscriptionCandidateCorrectionRule(
                source: " chat gp t ",
                aliases: [" 챗 지피티 ", "", "chat gp t", "챗 지피티", "CHAT GP T"],
                replacement: " ChatGPT ",
                confidence: 1.2,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "  personal mixed-language correction  "
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(1.3)
            ),
            TranscriptionCandidateCorrectionRule(
                source: "   ",
                aliases: ["ignored"],
                replacement: "ChatGPT",
                confidence: 0.5,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .never
            )
        ]

        #expect(rules.normalizedForEvaluation == [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 1,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "personal mixed-language correction"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(1.0)
            )
        ])
    }

    @Test func decodingLegacyRuleWithoutAliasesDefaultsToEmptyAliases() throws {
        let data = Data(
            """
            {
              "source": "chat gp t",
              "replacement": "ChatGPT",
              "confidence": 0.95,
              "evidence": {
                "kind": "candidateRule",
                "detail": "legacy"
              },
              "autoApplyPolicy": {
                "strategy": "ifConfidenceAtLeast",
                "minimumConfidence": 0.9
              }
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(TranscriptionCandidateCorrectionRule.self, from: data)

        #expect(decoded.source == "chat gp t")
        #expect(decoded.aliases.isEmpty)
        #expect(decoded.replacement == "ChatGPT")
    }

    @Test func matchingVariantsInferReplacementAcronymFormsWithoutCanonicalCollapsedReplacement() {
        let rule = TranscriptionCandidateCorrectionRule(
            source: "chat gp t",
            aliases: [],
            replacement: "ChatGPT",
            confidence: 0.95,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "replacement acronym inference"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        #expect(rule.matchingVariants.contains("chat gp t"))
        #expect(rule.matchingVariants.contains("chat g p t"))
        #expect(rule.matchingVariants.contains("chat 지피티"))
        #expect(!rule.matchingVariants.contains("chatgpt"))
        #expect(!rule.matchingVariants.contains("ChatGPT"))
    }

    @Test func applyingSuggestionUsesResolvedReplacementAndGuardsMissingSource() {
        let sourceText = "챗 지피티에서"
        let sourceRange = (sourceText as NSString).range(of: sourceText)
        let candidate = TranscriptionCandidateCorrection(
            sourceText: sourceText,
            replacement: "ChatGPT",
            resolvedReplacement: "ChatGPT에서",
            sourceRangeLocation: sourceRange.location,
            sourceRangeLength: sourceRange.length,
            confidence: 0.62,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "mixed-language alias heuristic"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        #expect(candidate.applying(to: "챗 지피티에서 확인") == "ChatGPT에서 확인")
        #expect(candidate.applying(to: "이미 수정된 텍스트") == nil)
    }

    @Test func applyingSuggestionUsesStoredSpanToAvoidWrongDuplicateOccurrence() {
        let text = "첫번째 챗 지피티 그리고 두번째 챗 지피티"
        let nsText = text as NSString
        let firstRange = nsText.range(of: "챗 지피티")
        let duplicateRange = nsText.range(
            of: "챗 지피티",
            options: [],
            range: NSRange(
                location: firstRange.location + firstRange.length,
                length: nsText.length - (firstRange.location + firstRange.length)
            )
        )
        let candidate = TranscriptionCandidateCorrection(
            sourceText: "챗 지피티",
            replacement: "ChatGPT",
            resolvedReplacement: "ChatGPT",
            sourceRangeLocation: duplicateRange.location,
            sourceRangeLength: duplicateRange.length,
            confidence: 0.62,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "duplicate-span safety"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        #expect(candidate.applying(to: text) == "첫번째 챗 지피티 그리고 두번째 ChatGPT")
        #expect(candidate.applying(to: "ChatGPT 그리고 두번째 챗 지피티") == nil)
    }

    @Test func promotingSuggestionUsesCanonicalSourceAndLearnsVisibleAlias() {
        let sourceText = "챗 지피티에서"
        let sourceRange = (sourceText as NSString).range(of: sourceText)
        let candidate = TranscriptionCandidateCorrection(
            sourceText: sourceText,
            canonicalSource: "chat gp t",
            replacement: "ChatGPT",
            resolvedReplacement: "ChatGPT에서",
            sourceRangeLocation: sourceRange.location,
            sourceRangeLength: sourceRange.length,
            confidence: 0.62,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "mixed-language alias heuristic"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        #expect(candidate.promotedAlwaysApplyRule == TranscriptionCandidateCorrectionRule(
            source: "chat gp t",
            aliases: ["챗 지피티"],
            replacement: "ChatGPT",
            confidence: 1,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "mixed-language alias heuristic"
            ),
            autoApplyPolicy: .always
        ))
    }

    @Test func promotedSuggestionMergesIntoExistingRuleAndUpgradesToAlwaysApply() {
        let sourceText = "챗 지피티에서"
        let sourceRange = (sourceText as NSString).range(of: sourceText)
        let candidate = TranscriptionCandidateCorrection(
            sourceText: sourceText,
            canonicalSource: "chat gp t",
            replacement: "ChatGPT",
            resolvedReplacement: "ChatGPT에서",
            sourceRangeLocation: sourceRange.location,
            sourceRangeLength: sourceRange.length,
            confidence: 0.62,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "mixed-language alias heuristic"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        let merged = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["chat g p t"],
                replacement: "ChatGPT",
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "existing heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ].upsertingPromotedSuggestion(candidate)

        #expect(merged == [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["chat g p t", "챗 지피티"],
                replacement: "ChatGPT",
                confidence: 1,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "existing heuristic"
                ),
                autoApplyPolicy: .always
            )
        ])
    }

    @Test func upsertingPromotedSuggestionPreservesIncompleteDraftRows() {
        let sourceText = "챗 지피티에서"
        let sourceRange = (sourceText as NSString).range(of: sourceText)
        let candidate = TranscriptionCandidateCorrection(
            sourceText: sourceText,
            canonicalSource: "chat gp t",
            replacement: "ChatGPT",
            resolvedReplacement: "ChatGPT에서",
            sourceRangeLocation: sourceRange.location,
            sourceRangeLength: sourceRange.length,
            confidence: 0.62,
            evidence: TranscriptionCorrectionEvidence(
                kind: .candidateRule,
                detail: "mixed-language alias heuristic"
            ),
            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
        )

        let merged = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: [],
                replacement: "ChatGPT",
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            ),
            TranscriptionCandidateCorrectionRule(
                source: "claud",
                aliases: [],
                replacement: "",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ].upsertingPromotedSuggestion(candidate)

        #expect(merged.count == 2)
        #expect(merged[0].autoApplyPolicy == .always)
        #expect(merged[1].source == "claud")
        #expect(merged[1].replacement.isEmpty)
    }
}
