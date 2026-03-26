import Foundation
import Testing
import VoiceInputCore
@testable import VoiceInput

@MainActor
@Suite("AppSettings Processing Tests")
struct AppSettingsProcessingTests {

    @Test func glossaryAndPresetRoundTripThroughDefaults() throws {
        let suiteName = "VoiceInputTests.AppSettingsProcessing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let glossary = [
            TranscriptionGlossaryItem(
                phrase: "OpenAI",
                replacement: "OpenAI",
                aliases: ["open ai"]
            )
        ]

        let first = AppSettings(defaults: defaults)
        first.transcriptionGlossary = glossary
        first.outputPreset = .polishedMessage

        let second = AppSettings(defaults: defaults)

        #expect(second.transcriptionGlossary == glossary)
        #expect(second.outputPreset == .polishedMessage)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func correctionsRoundTripThroughDefaults() throws {
        let suiteName = "VoiceInputTests.AppSettingsProcessing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let corrections = [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT"),
            TranscriptionCorrectionRule(source: "fig ma", replacement: "Figma")
        ]

        let first = AppSettings(defaults: defaults)
        first.transcriptionCorrections = corrections

        let second = AppSettings(defaults: defaults)

        #expect(second.transcriptionCorrections == corrections)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedSettingsSnapshotCarriesGlossaryAndPreset() {
        let suiteName = "VoiceInputTests.AppSettingsProcessing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.selectedLanguage = .korean
        settings.selectedModel = "large-v3"
        settings.autoInsertText = false
        settings.transcriptionGlossary = [
            TranscriptionGlossaryItem(
                phrase: "FigJam",
                replacement: "FigJam",
                aliases: ["fig jam"]
            )
        ]
        settings.outputPreset = .meetingNotes

        let snapshot = settings.sharedSettingsSnapshot

        #expect(snapshot.selectedLanguage == .korean)
        #expect(snapshot.selectedModel == "large-v3")
        #expect(snapshot.autoInsertText == false)
        #expect(snapshot.glossary.first?.replacement == "FigJam")
        #expect(snapshot.outputPreset == .meetingNotes)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedSettingsSnapshotCarriesCorrections() {
        let suiteName = "VoiceInputTests.AppSettingsProcessing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.transcriptionCorrections = [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ]

        let snapshot = settings.sharedSettingsSnapshot

        #expect(snapshot.corrections == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionsRoundTripThroughDefaultsAndSnapshot() throws {
        let suiteName = "VoiceInputTests.AppSettingsProcessing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 0.95,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "personal mixed-language correction"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]

        let first = AppSettings(defaults: defaults)
        first.transcriptionCandidateCorrections = candidateCorrections

        let second = AppSettings(defaults: defaults)
        #expect(second.transcriptionCandidateCorrections == candidateCorrections)

        let snapshot = second.sharedSettingsSnapshot
        #expect(snapshot.candidateCorrections == candidateCorrections)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
