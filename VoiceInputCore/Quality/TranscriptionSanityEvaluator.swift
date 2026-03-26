import Foundation

public enum TranscriptionSanityEvaluator {
    public static func keywordMatchScore(transcription: String, expectedKeywords: [String]) -> Double {
        let normalizedTranscription = normalize(transcription)
        let normalizedKeywords = Set(expectedKeywords.map(normalize).filter { !$0.isEmpty })

        guard !normalizedKeywords.isEmpty else {
            return 1.0
        }

        let matched = normalizedKeywords.filter { normalizedTranscription.contains($0) }
        return Double(matched.count) / Double(normalizedKeywords.count)
    }

    public static func passes(
        transcription: String,
        expectedKeywords: [String],
        minimumScore: Double = 0.9
    ) -> Bool {
        keywordMatchScore(transcription: transcription, expectedKeywords: expectedKeywords) >= minimumScore
    }

    private static func normalize(_ input: String) -> String {
        let folded = input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let stripped = folded.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: " ",
            options: .regularExpression
        )

        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
