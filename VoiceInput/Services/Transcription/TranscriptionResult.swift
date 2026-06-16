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
            rawText: text,
            cleanText: text,
            segments: segments
        )
    }

    struct Segment: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
}

struct TranscriptionDiagnostics: Sendable {
    private static let maxPreviewCharacters = 240
    private static let maxSegmentPreviewCount = 3

    let rawText: String
    let cleanText: String
    let segmentCount: Int
    let segmentPreview: String

    init(
        rawText: String,
        cleanText: String,
        segments: [TranscriptionResult.Segment]
    ) {
        self.rawText = rawText
        self.cleanText = cleanText
        self.segmentCount = segments.count
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
        "model=\(model), requestedLanguage=\(requestedLanguage), audioDuration=\(String(format: "%.1f", audioDuration))s, rawText='\(Self.preview(rawText))', cleanText='\(Self.preview(cleanText))', segmentCount=\(segmentCount), segmentPreview='\(segmentPreview)'"
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
