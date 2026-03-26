import Foundation
import Testing
@testable import VoiceInputCore

@Suite("iOS Shared Settings Sync Tests")
struct IOSSharedSettingsSyncTests {

    @Test func settingsAreSharedAcrossHostAndKeyboardReaders() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.selectedLanguage = .korean
            settings.selectedModel = "base"
            settings.autoInsertText = false
            settings.keepQuickNoteHistory = false
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "OpenAI",
                    replacement: "OpenAI",
                    aliases: ["open ai"]
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let synced = keyboardStore.load()
        #expect(synced.selectedLanguage == .korean)
        #expect(synced.selectedModel == "base")
        #expect(synced.autoInsertText == false)
        #expect(synced.keepQuickNoteHistory == false)
        #expect(synced.glossary.first?.replacement == "OpenAI")
        #expect(synced.outputPreset == .polishedMessage)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationProducesQuickAndProCorrections() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "OpenAI",
                    replacement: "OpenAI",
                    aliases: ["open ai", "오픈에이아이"]
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  ping 오픈에이아이 about the launch  ")

        #expect(result.processedText == "Ping OpenAI about the launch.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationHandlesFlexibleSeparatorsAndParticles() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "OpenAI",
                    replacement: "OpenAI",
                    aliases: ["open ai"]
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  ping open-ai에서 follow up  ")

        #expect(result.processedText == "Ping OpenAI에서 follow up.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationHandlesJapaneseParticles() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "OpenAI",
                    replacement: "OpenAI",
                    aliases: ["open ai"]
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  note open aiで sync  ")

        #expect(result.processedText == "Note OpenAIで sync.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationInfersEnglishAliasesWithoutPersistingThem() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "오픈에이아이",
                    replacement: "OpenAI",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  note open ai for launch  ")

        #expect(result.processedText == "Note OpenAI for launch.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationNormalizesCompactModelVariantsWithoutPersistingAliases() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "GPT4o",
                    replacement: "GPT-4o",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  compare gpt 4o and gpt4o  ")

        #expect(result.processedText == "Compare GPT-4o and GPT-4o.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationNormalizesExpandedCompactQualifiersWithoutPersistingAliases() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "M2Ultra",
                    replacement: "M2 Ultra",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  compare m2_ultra  ")

        #expect(result.processedText == "Compare M2 Ultra.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationNormalizesDottedModelVersionsWithoutPersistingAliases() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "Claude3.7",
                    replacement: "Claude-3.7",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  compare claude 3.7 and claude3.7  ")

        #expect(result.processedText == "Compare Claude-3.7 and Claude-3.7.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationNormalizesFullDottedModelVariantsWithoutPersistingAliases() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "Claude3.7Sonnet",
                    replacement: "Claude 3.7 Sonnet",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  compare claude-3.7-sonnet에서  ")

        #expect(result.processedText == "Compare Claude 3.7 Sonnet에서.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedGlossaryConfigurationNormalizesAdditionalFullDottedLabelsWithoutPersistingAliases() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "Claude3.7Opus",
                    replacement: "Claude 3.7 Opus",
                    aliases: []
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let loadedSettings = keyboardStore.load()
        #expect(loadedSettings.glossary.first?.aliases.isEmpty == true)

        let sharedConfiguration = loadedSettings.postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  compare claude-3.7-opus에서  ")

        #expect(result.processedText == "Compare Claude 3.7 Opus에서.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func sharedCorrectionRulesApplyAcrossQuickAndProProcessing() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.corrections = [
                TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
            ]
            settings.outputPreset = .polishedMessage
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let processor = PostTranscriptionProcessor(configuration: sharedConfiguration)
        let result = processor.process("  ping chat gp t after lunch  ")

        #expect(result.processedText == "Ping ChatGPT after lunch.")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionContractFlowsThroughSharedSettingsStore() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: [],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile mixed-language correction"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .polishedMessage
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("  ping chat gp t after lunch  ")

        #expect(sharedConfiguration.candidateCorrections.count == 1)
        #expect(result.processedText == "Ping ChatGPT after lunch.")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.evidence.kind == .candidateRule)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionsHandleFlexibleSeparatorsAndAttachedSuffixesAcrossSharedSettings() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: [],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile mixed-language correction"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .verbatim
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("chat-gp-t에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionAliasesFlowThroughSharedSettingsStore() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: ["챗 지피티"],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile mixed-language correction"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .verbatim
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("챗 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionInferenceFlowsThroughSharedSettingsStore() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: [],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile acronym phonetic heuristic"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .verbatim
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("chat 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionSeparatedAcronymInferenceFlowsThroughSharedSettingsStore() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: [],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile separated acronym heuristic"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .verbatim
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("chat g p t에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidateCorrectionsDoNotTreatKoreanWordPrefixesAsParticlesAcrossSharedSettings() throws {
        let suiteName = "voiceinput.tests.mobile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let hostStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let keyboardStore = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)

        hostStore.update { settings in
            settings.candidateCorrections = [
                TranscriptionCandidateCorrectionRule(
                    source: "chat gp t",
                    aliases: [],
                    replacement: "ChatGPT",
                    confidence: 0.95,
                    evidence: TranscriptionCorrectionEvidence(
                        kind: .candidateRule,
                        detail: "shared mobile mixed-language correction"
                    ),
                    autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                )
            ]
            settings.outputPreset = .verbatim
        }

        let sharedConfiguration = keyboardStore.load().postTranscriptionProcessingConfiguration
        let result = PostTranscriptionProcessor(configuration: sharedConfiguration)
            .process("chat-gp-t에러")

        #expect(result.processedText == "chat-gp-t에러")
        #expect(result.appliedCorrections.isEmpty)
        #expect(result.suppressedCandidates.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

@Suite("iOS Recording State Transition Tests")
struct IOSRecordingStateTransitionTests {

    @Test func stateMachineTracksHappyPath() {
        var machine = DictationSessionStateMachine()

        let started = machine.startRecording()
        #expect(started)

        let beganTranscription = machine.beginTranscription()
        #expect(beganTranscription)

        let beganInsertion = machine.beginInsertion(text: "hello")
        #expect(beganInsertion)
        #expect(machine.recordingState == .inserting(text: "hello"))

        machine.reset()
        #expect(machine.recordingState == .idle)
    }

    @Test func stateMachineRejectsOutOfOrderTransitions() {
        var machine = DictationSessionStateMachine()

        let transcribeWithoutRecording = machine.beginTranscription()
        #expect(transcribeWithoutRecording == false)

        let insertWithoutRecording = machine.beginInsertion(text: "text")
        #expect(insertWithoutRecording == false)

        _ = machine.startRecording()
        let insertWithoutTranscribing = machine.beginInsertion(text: "text")
        #expect(insertWithoutTranscribing == false)
    }
}
