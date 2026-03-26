import Foundation

public struct SharedSettings: Codable, Equatable, Sendable {
    public var selectedLanguage: DictationLanguage
    public var selectedModel: String
    public var recordingMode: RecordingMode
    public var autoInsertText: Bool
    public var enablePunctuation: Bool
    public var keepQuickNoteHistory: Bool
    public var glossary: [TranscriptionGlossaryItem]
    public var corrections: [TranscriptionCorrectionRule]
    public var candidateCorrections: [TranscriptionCandidateCorrectionRule]
    public var outputPreset: TranscriptionOutputPreset

    public init(
        selectedLanguage: DictationLanguage,
        selectedModel: String,
        recordingMode: RecordingMode,
        autoInsertText: Bool,
        enablePunctuation: Bool,
        keepQuickNoteHistory: Bool,
        glossary: [TranscriptionGlossaryItem] = [],
        corrections: [TranscriptionCorrectionRule] = [],
        candidateCorrections: [TranscriptionCandidateCorrectionRule] = [],
        outputPreset: TranscriptionOutputPreset = .verbatim
    ) {
        self.selectedLanguage = selectedLanguage
        self.selectedModel = selectedModel
        self.recordingMode = recordingMode
        self.autoInsertText = autoInsertText
        self.enablePunctuation = enablePunctuation
        self.keepQuickNoteHistory = keepQuickNoteHistory
        self.glossary = glossary.normalizedForPersistence
        self.corrections = corrections.normalizedForPersistence
        self.candidateCorrections = candidateCorrections.normalizedForEvaluation
        self.outputPreset = outputPreset
    }

    public static let `default` = SharedSettings(
        selectedLanguage: .auto,
        selectedModel: "small",
        recordingMode: .toggle,
        autoInsertText: true,
        enablePunctuation: true,
        keepQuickNoteHistory: true,
        glossary: [],
        corrections: [],
        candidateCorrections: [],
        outputPreset: .verbatim
    )

    public var postTranscriptionProcessingConfiguration: PostTranscriptionProcessingConfiguration {
        PostTranscriptionProcessingConfiguration(
            glossary: glossary.normalizedForPersistence,
            corrections: corrections.normalizedForPersistence,
            candidateCorrections: candidateCorrections.normalizedForEvaluation,
            formatting: .preserveExactOutput,
            outputPreset: outputPreset
        )
    }

    public var sanitizedForPersistence: SharedSettings {
        SharedSettings(
            selectedLanguage: selectedLanguage,
            selectedModel: selectedModel,
            recordingMode: recordingMode,
            autoInsertText: autoInsertText,
            enablePunctuation: enablePunctuation,
            keepQuickNoteHistory: keepQuickNoteHistory,
            glossary: glossary,
            corrections: corrections,
            candidateCorrections: candidateCorrections,
            outputPreset: outputPreset
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedLanguage
        case selectedModel
        case recordingMode
        case autoInsertText
        case enablePunctuation
        case keepQuickNoteHistory
        case glossary
        case corrections
        case candidateCorrections
        case outputPreset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedLanguage = try container.decode(DictationLanguage.self, forKey: .selectedLanguage)
        selectedModel = try container.decode(String.self, forKey: .selectedModel)
        recordingMode = try container.decode(RecordingMode.self, forKey: .recordingMode)
        autoInsertText = try container.decode(Bool.self, forKey: .autoInsertText)
        enablePunctuation = try container.decode(Bool.self, forKey: .enablePunctuation)
        keepQuickNoteHistory = try container.decode(Bool.self, forKey: .keepQuickNoteHistory)
        glossary = (try container.decodeIfPresent([TranscriptionGlossaryItem].self, forKey: .glossary) ?? []).normalizedForPersistence
        corrections = (try container.decodeIfPresent([TranscriptionCorrectionRule].self, forKey: .corrections) ?? []).normalizedForPersistence
        candidateCorrections = (try container.decodeIfPresent([TranscriptionCandidateCorrectionRule].self, forKey: .candidateCorrections) ?? []).normalizedForEvaluation
        outputPreset = try container.decodeIfPresent(TranscriptionOutputPreset.self, forKey: .outputPreset) ?? .verbatim
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(recordingMode, forKey: .recordingMode)
        try container.encode(autoInsertText, forKey: .autoInsertText)
        try container.encode(enablePunctuation, forKey: .enablePunctuation)
        try container.encode(keepQuickNoteHistory, forKey: .keepQuickNoteHistory)
        try container.encode(glossary.normalizedForPersistence, forKey: .glossary)
        try container.encode(corrections.normalizedForPersistence, forKey: .corrections)
        try container.encode(candidateCorrections.normalizedForEvaluation, forKey: .candidateCorrections)
        try container.encode(outputPreset, forKey: .outputPreset)
    }
}
