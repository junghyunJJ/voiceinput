import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let language: String
    let segments: [Segment]
    let duration: TimeInterval
    let diagnostics: TranscriptionDiagnostics

    init(
        text: String,
        language: String,
        segments: [Segment],
        duration: TimeInterval,
        diagnostics: TranscriptionDiagnostics? = nil
    ) {
        self.text = text
        self.language = language
        self.segments = segments
        self.duration = duration
        self.diagnostics = diagnostics ?? TranscriptionDiagnostics(
            attempt: "primary",
            rawText: text,
            cleanText: text,
            segments: segments
        )
    }

    struct Segment: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        let temperature: Float
        let avgLogprob: Float
        let compressionRatio: Float
        let noSpeechProb: Float

        init(
            text: String,
            start: TimeInterval,
            end: TimeInterval,
            temperature: Float = 0,
            avgLogprob: Float = 0,
            compressionRatio: Float = 0,
            noSpeechProb: Float = 0
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.temperature = temperature
            self.avgLogprob = avgLogprob
            self.compressionRatio = compressionRatio
            self.noSpeechProb = noSpeechProb
        }
    }
}

struct TranscriptionDiagnostics: Sendable {
    private static let maxPreviewCharacters = 240
    private static let maxSegmentPreviewCount = 3

    let attempt: String
    let rawText: String
    let cleanText: String
    let segmentCount: Int
    let segmentStats: String
    let segmentPreview: String
    var hasEmptyTextWithSegments: Bool { rawText.isEmpty && cleanText.isEmpty && segmentCount > 0 }

    init(
        attempt: String = "primary",
        rawText: String,
        cleanText: String,
        segments: [TranscriptionResult.Segment]
    ) {
        self.attempt = attempt
        self.rawText = rawText
        self.cleanText = cleanText
        self.segmentCount = segments.count
        self.segmentStats = segments
            .prefix(Self.maxSegmentPreviewCount)
            .map {
                String(
                    format: "temp=%.2f avgLogprob=%.2f compression=%.2f noSpeech=%.2f",
                    $0.temperature,
                    $0.avgLogprob,
                    $0.compressionRatio,
                    $0.noSpeechProb
                )
            }
            .joined(separator: " | ")
        self.segmentPreview = segments
            .prefix(Self.maxSegmentPreviewCount)
            .map { Self.preview($0.text) }
            .joined(separator: " | ")
    }

    func logSummary(
        model: String,
        requestedLanguage: String,
        audioDuration: TimeInterval
    ) -> String {
        "attempt=\(attempt), model=\(model), requestedLanguage=\(requestedLanguage), audioDuration=\(String(format: "%.1f", audioDuration))s, rawText='\(Self.preview(rawText))', cleanText='\(Self.preview(cleanText))', segmentCount=\(segmentCount), segmentStats='\(segmentStats)', segmentPreview='\(segmentPreview)'"
    }

    private static func preview(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        guard singleLine.count > maxPreviewCharacters else {
            return singleLine
        }

        return String(singleLine.prefix(maxPreviewCharacters)) + "..."
    }
}
