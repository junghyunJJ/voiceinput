import Foundation
import Testing
@testable import VoiceInputCore

@Suite("iOS Transcription Sanity Tests")
struct IOSTranscriptionSanityTests {

    @Test func englishFixedPhrasePassesNinetyPercentThreshold() {
        let expectedKeywords = [
            "project", "update", "meeting", "tomorrow", "nine", "am", "summary", "send", "team", "thanks"
        ]
        let transcription = "Project update meeting tomorrow at nine AM. Please send the summary to the team, thanks."

        let score = TranscriptionSanityEvaluator.keywordMatchScore(
            transcription: transcription,
            expectedKeywords: expectedKeywords
        )

        #expect(score >= 0.9)
        #expect(TranscriptionSanityEvaluator.passes(transcription: transcription, expectedKeywords: expectedKeywords))
    }

    @Test func koreanFixedPhrasePassesNinetyPercentThreshold() {
        let expectedKeywords = [
            "오늘", "회의", "업데이트", "내일", "오전", "아홉시", "요약", "공유", "팀", "감사"
        ]
        let transcription = "오늘 회의 업데이트를 정리해서 내일 오전 아홉시에 팀에 요약 공유할게요. 감사합니다."

        let score = TranscriptionSanityEvaluator.keywordMatchScore(
            transcription: transcription,
            expectedKeywords: expectedKeywords
        )

        #expect(score >= 0.9)
        #expect(TranscriptionSanityEvaluator.passes(transcription: transcription, expectedKeywords: expectedKeywords))
    }

    @Test func lowCoverageFailsThreshold() {
        let expectedKeywords = ["project", "update", "meeting", "tomorrow", "summary"]
        let transcription = "Thanks for checking in."

        let score = TranscriptionSanityEvaluator.keywordMatchScore(
            transcription: transcription,
            expectedKeywords: expectedKeywords
        )

        #expect(score < 0.9)
        #expect(!TranscriptionSanityEvaluator.passes(transcription: transcription, expectedKeywords: expectedKeywords))
    }
}
