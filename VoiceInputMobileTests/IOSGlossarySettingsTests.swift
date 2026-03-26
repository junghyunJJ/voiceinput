import Foundation
import Testing
import VoiceInputCore
import VoiceInputMobileShared
@testable import VoiceInputiOS

@Suite("iOS Glossary Settings Tests")
struct IOSGlossarySettingsTests {

    @MainActor
    @Test func viewModelLoadsGlossaryFromSharedSettings() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.update { settings in
            settings.glossary = [
                TranscriptionGlossaryItem(
                    phrase: "OpenAI",
                    replacement: "OpenAI",
                    aliases: ["open ai", "openai"]
                )
            ]
        }

        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        #expect(viewModel.glossary.count == 1)
        #expect(viewModel.glossary.first?.phrase == "OpenAI")
        #expect(viewModel.glossary.first?.aliases == ["open ai", "openai"])
    }

    @MainActor
    @Test func persistSettingsSanitizesAndSavesGlossaryEntries() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.glossary = [
            TranscriptionGlossaryItem(
                phrase: " OpenAI ",
                replacement: " OpenAI ",
                aliases: [" open ai ", "", "openai", "openai"]
            ),
            TranscriptionGlossaryItem(
                phrase: "   ",
                replacement: "   ",
                aliases: []
            )
        ]

        viewModel.persistSettings()
        let saved = store.load().glossary

        #expect(saved.count == 1)
        #expect(saved.first?.phrase == "OpenAI")
        #expect(saved.first?.replacement == "OpenAI")
        #expect(saved.first?.aliases == ["open ai", "openai"])
    }

    @MainActor
    @Test func viewModelLoadsCorrectionsFromSharedSettings() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.update { settings in
            settings.corrections = [
                TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
            ]
        }

        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        #expect(viewModel.corrections == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])
    }

    @MainActor
    @Test func persistSettingsSanitizesAndSavesCorrectionRules() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.corrections = [
            TranscriptionCorrectionRule(source: " chat gp t ", replacement: " ChatGPT "),
            TranscriptionCorrectionRule(source: "   ", replacement: "   ")
        ]

        viewModel.persistSettings()

        #expect(store.load().corrections == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])
    }

    @MainActor
    @Test func viewModelLoadsCandidateCorrectionsFromSharedSettings() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.update { settings in
            settings.candidateCorrections = [
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
        }

        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        #expect(viewModel.candidateCorrections.count == 1)
        #expect(viewModel.candidateCorrections.first?.source == "chat gp t")
        #expect(viewModel.candidateCorrections.first?.aliases == ["챗 지피티"])
    }

    @MainActor
    @Test func persistSettingsSanitizesAndSavesCandidateCorrections() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: " chat gp t ",
                aliases: [" 챗 지피티 ", "", "챗 지피티", "CHAT GP T"],
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
                replacement: "   ",
                confidence: 0.5,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .never
            )
        ]

        viewModel.persistSettings()

        #expect(store.load().candidateCorrections == [
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

    @MainActor
    @Test func persistSettingsKeepsIncompleteCandidateDraftRowsInMemory() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: [],
                replacement: "ChatGPT",
                confidence: 0.95,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            ),
            TranscriptionCandidateCorrectionRule(
                source: "claud",
                aliases: [],
                replacement: "",
                confidence: 0.8,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .never
            )
        ]

        viewModel.persistSettings()

        #expect(viewModel.candidateCorrections.count == 2)
        #expect(viewModel.candidateCorrections[1].source == "claud")
        #expect(store.load().candidateCorrections.count == 1)
    }

    @MainActor
    @Test func refreshSuppressedCandidateSuggestionsUsesCurrentTranscribedText() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "챗 지피티에서 확인"

        viewModel.refreshSuppressedCandidateSuggestions()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceText == "챗 지피티에서")
        #expect(viewModel.suppressedCandidateSuggestions.first?.resolvedReplacement == "ChatGPT에서")
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceRangeLocation == 0)
    }

    @MainActor
    @Test func refreshSuppressedCandidateSuggestionsDedupesOverlappingCandidates() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 0.6,
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
                confidence: 0.73,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "higher confidence overlap"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "챗 지피티에서 확인"

        viewModel.refreshSuppressedCandidateSuggestions()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.confidence == 0.73)
        #expect(viewModel.suppressedCandidateSuggestions.first?.canonicalSource == nil)
    }

    @MainActor
    @Test func refreshSuppressedCandidateSuggestionsCollapsesOverlappingSameFixCandidates() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: [],
                replacement: "ChatGPT",
                confidence: 0.6,
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
                confidence: 0.73,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "partial overlap"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "chat gp t 확인"

        viewModel.refreshSuppressedCandidateSuggestions()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceText == "chat gp t")
        #expect(viewModel.suppressedCandidateSuggestions.first?.resolvedReplacement == "ChatGPT")
        #expect(viewModel.suppressedCandidateSuggestions.first?.confidence == 0.6)
        #expect(viewModel.suppressedCandidateSuggestions.first?.canonicalSource == nil)
    }

    @MainActor
    @Test func viewModelLoadsSavedKeyboardResultIntoDraft() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Saved from app", forKey: MobileConstants.lastTranscriptionKey)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        #expect(viewModel.transcribedText == "Saved from app")
        #expect(viewModel.savedKeyboardText == "Saved from app")
        #expect(viewModel.hasSavedKeyboardResult)
        #expect(!viewModel.hasUnsavedKeyboardEdits)
    }

    @MainActor
    @Test func manualDraftEditsStayLocalUntilPasteLastIsExplicitlyUpdated() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Saved from app", forKey: MobileConstants.lastTranscriptionKey)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.transcribedText = "Saved from app with edits"

        #expect(viewModel.hasUnsavedKeyboardEdits)
        #expect(viewModel.canUpdatePasteLast)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "Saved from app")

        let updated = viewModel.updatePasteLastFromCurrentDraft()

        #expect(updated)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "Saved from app with edits")
        #expect(viewModel.savedKeyboardText == "Saved from app with edits")
        #expect(!viewModel.hasUnsavedKeyboardEdits)
    }

    @MainActor
    @Test func updatingPasteLastWithEmptyDraftClearsSavedKeyboardResult() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Saved from app", forKey: MobileConstants.lastTranscriptionKey)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.transcribedText = ""

        let updated = viewModel.updatePasteLastFromCurrentDraft()

        #expect(updated)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == nil)
        #expect(viewModel.savedKeyboardText.isEmpty)
        #expect(!viewModel.hasSavedKeyboardResult)
        #expect(!viewModel.hasUnsavedKeyboardEdits)
    }

    @MainActor
    @Test func copySavedKeyboardResultCopiesSavedTextWithoutMutatingDraftOrDefaults() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Saved from app", forKey: MobileConstants.lastTranscriptionKey)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        var copiedText: String?
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true,
            copyToClipboard: { copiedText = $0 }
        )

        viewModel.transcribedText = "Saved from app with edits"

        let copied = viewModel.copySavedKeyboardResult()

        #expect(copied)
        #expect(copiedText == "Saved from app")
        #expect(viewModel.transcribedText == "Saved from app with edits")
        #expect(viewModel.savedKeyboardText == "Saved from app")
        #expect(viewModel.hasUnsavedKeyboardEdits)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "Saved from app")
    }

    @MainActor
    @Test func copySavedKeyboardResultFailsWhenNoSavedTextExists() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        var copiedText: String?
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true,
            copyToClipboard: { copiedText = $0 }
        )

        let copied = viewModel.copySavedKeyboardResult()

        #expect(!copied)
        #expect(copiedText == nil)
        #expect(viewModel.savedKeyboardText.isEmpty)
        #expect(!viewModel.hasSavedKeyboardResult)
    }

    @MainActor
    @Test func applySuppressedCandidateSuggestionUpdatesTextAndSharedDefaults() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "챗 지피티에서 확인"
        viewModel.refreshSuppressedCandidateSuggestions()

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)

        #expect(applied)
        #expect(viewModel.transcribedText == "ChatGPT에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.isEmpty)
        #expect(
            defaults.string(forKey: MobileConstants.lastTranscriptionKey)
                == "ChatGPT에서 확인"
        )
    }

    @MainActor
    @Test func applySuppressedCandidateSuggestionUsesWidestOverlapWinner() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
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
                confidence: 0.73,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "partial overlap"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "chat gp t 확인"
        viewModel.refreshSuppressedCandidateSuggestions()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceText == "chat gp t")

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)

        #expect(applied)
        #expect(viewModel.transcribedText == "ChatGPT 확인")
        #expect(
            defaults.string(forKey: MobileConstants.lastTranscriptionKey)
                == "ChatGPT 확인"
        )
    }

    @MainActor
    @Test func copySuppressedCandidateSuggestionCopiesCorrectedTextWithoutMutatingDraftOrDefaults() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        var copiedText: String?
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true,
            copyToClipboard: { copiedText = $0 }
        )

        defaults.set("unchanged", forKey: MobileConstants.lastTranscriptionKey)
        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["챗 지피티"],
                replacement: "ChatGPT",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "챗 지피티에서 확인"
        viewModel.refreshSuppressedCandidateSuggestions()

        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(copied)
        #expect(copiedText == "ChatGPT에서 확인")
        #expect(viewModel.transcribedText == "챗 지피티에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "unchanged")
    }

    @MainActor
    @Test func refreshSuppressedCandidateSuggestionsTracksVisiblePolishedTextSpan() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.outputPreset = .polishedMessage
        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: [],
                replacement: "ChatGPT",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "polished-message span alignment"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "Ping chat gp t after lunch."

        viewModel.refreshSuppressedCandidateSuggestions()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceRangeLocation == 5)
        #expect(viewModel.applySuppressedCandidateSuggestion(at: 0))
        #expect(viewModel.transcribedText == "Ping ChatGPT after lunch.")
    }

    @MainActor
    @Test func applySuppressedCandidateSuggestionFailsWhenSourceNoLongerExists() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.suppressedCandidateSuggestions = [
            TranscriptionCandidateCorrection(
                sourceText: "챗 지피티에서",
                replacement: "ChatGPT",
                resolvedReplacement: "ChatGPT에서",
                sourceRangeLocation: 0,
                sourceRangeLength: ("챗 지피티에서" as NSString).length,
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "이미 수정된 텍스트"

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)

        #expect(!applied)
        #expect(viewModel.transcribedText == "이미 수정된 텍스트")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
    }

    @MainActor
    @Test func copySuppressedCandidateSuggestionFailsWhenSourceNoLongerExists() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        var copiedText: String?
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true,
            copyToClipboard: { copiedText = $0 }
        )

        defaults.set("unchanged", forKey: MobileConstants.lastTranscriptionKey)
        viewModel.suppressedCandidateSuggestions = [
            TranscriptionCandidateCorrection(
                sourceText: "챗 지피티에서",
                replacement: "ChatGPT",
                resolvedReplacement: "ChatGPT에서",
                sourceRangeLocation: 0,
                sourceRangeLength: ("챗 지피티에서" as NSString).length,
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "이미 수정된 텍스트"

        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(!copied)
        #expect(copiedText == nil)
        #expect(viewModel.transcribedText == "이미 수정된 텍스트")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "unchanged")
    }

    @MainActor
    @Test func saveSuppressedCandidateSuggestionAsRulePersistsAlwaysOnRuleAndLearnsAlias() throws {
        let suiteName = "voiceinput.tests.ios.glossary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let viewModel = IOSDictationViewModel(
            sharedDefaults: defaults,
            settingsStore: store,
            skipAppGroupSetup: true
        )

        viewModel.candidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["chat g p t"],
                replacement: "ChatGPT",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "existing heuristic"
                ),
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
        ]
        viewModel.suppressedCandidateSuggestions = [
            TranscriptionCandidateCorrection(
                sourceText: "챗 지피티에서",
                canonicalSource: "chat gp t",
                replacement: "ChatGPT",
                resolvedReplacement: "ChatGPT에서",
                sourceRangeLocation: 0,
                sourceRangeLength: ("챗 지피티에서" as NSString).length,
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        viewModel.transcribedText = "챗 지피티에서 확인"
        defaults.set("unchanged", forKey: MobileConstants.lastTranscriptionKey)

        let saved = viewModel.saveSuppressedCandidateSuggestionAsRule(at: 0)

        #expect(saved)
        #expect(viewModel.candidateCorrections == [
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
            ),
            TranscriptionCandidateCorrectionRule(
                source: "claud",
                aliases: [],
                replacement: "",
                confidence: 0.6,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ])
        #expect(store.load().candidateCorrections == [
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
        #expect(viewModel.transcribedText == "ChatGPT에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.isEmpty)
        #expect(defaults.string(forKey: MobileConstants.lastTranscriptionKey) == "ChatGPT에서 확인")

        let result = PostTranscriptionProcessor(
            configuration: store.load().postTranscriptionProcessingConfiguration
        )
        .process("챗 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)
    }
}
