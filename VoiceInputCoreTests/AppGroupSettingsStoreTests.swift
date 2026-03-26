import Foundation
import Testing
@testable import VoiceInputCore

@Suite("App Group Settings Store Tests")
struct AppGroupSettingsStoreTests {

    @Test func loadsDefaultValuesWhenNoDataExists() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let settings = store.load()

        #expect(settings == .default)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func persistsSettingsAcrossInstances() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let writer = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        writer.save(
            SharedSettings(
                selectedLanguage: .korean,
                selectedModel: "large-v3",
                recordingMode: .pushToTalk,
                autoInsertText: false,
                enablePunctuation: true,
                keepQuickNoteHistory: false,
                glossary: [
                    TranscriptionGlossaryItem(
                        phrase: "OpenAI",
                        replacement: "OpenAI",
                        aliases: ["open ai"]
                    )
                ],
                corrections: [
                    TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
                ],
                outputPreset: .polishedMessage
            )
        )

        let reader = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let loaded = reader.load()

        #expect(loaded.selectedLanguage == .korean)
        #expect(loaded.selectedModel == "large-v3")
        #expect(loaded.recordingMode == .pushToTalk)
        #expect(loaded.autoInsertText == false)
        #expect(loaded.enablePunctuation == true)
        #expect(loaded.keepQuickNoteHistory == false)
        #expect(loaded.glossary.count == 1)
        #expect(loaded.glossary.first?.replacement == "OpenAI")
        #expect(loaded.corrections == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])
        #expect(loaded.outputPreset == .polishedMessage)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func updateMutatesAndSavesLatestSettings() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.update { settings in
            settings.selectedLanguage = .english
            settings.selectedModel = "base"
            settings.autoInsertText = false
        }

        let loaded = store.load()
        #expect(loaded.selectedLanguage == .english)
        #expect(loaded.selectedModel == "base")
        #expect(loaded.autoInsertText == false)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func saveNormalizesGlossaryEntries() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.save(
            SharedSettings(
                selectedLanguage: .auto,
                selectedModel: "small",
                recordingMode: .toggle,
                autoInsertText: true,
                enablePunctuation: true,
                keepQuickNoteHistory: true,
                glossary: [
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
                ],
                corrections: [
                    TranscriptionCorrectionRule(source: " chat gp t ", replacement: " ChatGPT "),
                    TranscriptionCorrectionRule(source: "   ", replacement: "   ")
                ],
                outputPreset: .polishedMessage
            )
        )

        let loaded = store.load()

        #expect(loaded.glossary.count == 1)
        #expect(loaded.glossary.first?.phrase == "OpenAI")
        #expect(loaded.glossary.first?.replacement == "OpenAI")
        #expect(loaded.glossary.first?.aliases == ["open ai", "openai"])
        #expect(loaded.corrections == [
            TranscriptionCorrectionRule(source: "chat gp t", replacement: "ChatGPT")
        ])

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func loadsLegacyHotkeyModeDuringMigration() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(RecordingMode.pushToTalk.rawValue, forKey: SharedSettingsStoreKey.hotkeyMode)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let loaded = store.load()

        #expect(loaded.recordingMode == .pushToTalk)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func saveMirrorsRecordingModeToLegacyHotkeyKey() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        store.save(
            SharedSettings(
                selectedLanguage: .english,
                selectedModel: "small",
                recordingMode: .pushToTalk,
                autoInsertText: true,
                enablePunctuation: true,
                keepQuickNoteHistory: true,
                glossary: [],
                corrections: [],
                outputPreset: .verbatim
            )
        )

        let mirrored = defaults.string(forKey: SharedSettingsStoreKey.hotkeyMode)
        #expect(mirrored == RecordingMode.pushToTalk.rawValue)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func legacyBlobWithoutGlossaryAndPresetFallsBackToDefaults() throws {
        struct LegacySharedSettingsV1: Codable {
            var selectedLanguage: DictationLanguage
            var selectedModel: String
            var recordingMode: RecordingMode
            var autoInsertText: Bool
            var enablePunctuation: Bool
            var keepQuickNoteHistory: Bool
        }

        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let legacyData = try JSONEncoder().encode(
            LegacySharedSettingsV1(
                selectedLanguage: .english,
                selectedModel: "base",
                recordingMode: .toggle,
                autoInsertText: true,
                enablePunctuation: false,
                keepQuickNoteHistory: true
            )
        )
        defaults.set(legacyData, forKey: SharedSettingsStoreKey.settingsBlob)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let loaded = store.load()

        #expect(loaded.selectedLanguage == .english)
        #expect(loaded.selectedModel == "base")
        #expect(loaded.glossary.isEmpty)
        #expect(loaded.corrections.isEmpty)
        #expect(loaded.outputPreset == .verbatim)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func strictPolicyRejectsInvalidAppGroupIdentifier() {
        #expect(throws: AppGroupSettingsStoreError.self) {
            _ = try AppGroupSettingsStore(
                appGroupIdentifier: "invalid-app-group",
                validationPolicy: .requireAppGroup
            )
        }
    }

    @Test func strictPolicyRejectsMissingAppGroupIdentifier() {
        #expect(throws: AppGroupSettingsStoreError.self) {
            _ = try AppGroupSettingsStore(
                appGroupIdentifier: nil,
                validationPolicy: .requireAppGroup
            )
        }
    }

    @Test func corruptedBlobFallsBackToLegacyKeys() throws {
        let suiteName = "voiceinput.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(Data("not-json".utf8), forKey: SharedSettingsStoreKey.settingsBlob)
        defaults.set(DictationLanguage.korean.rawValue, forKey: SharedSettingsStoreKey.selectedLanguage)
        defaults.set("base", forKey: SharedSettingsStoreKey.selectedModel)

        let store = try AppGroupSettingsStore(appGroupIdentifier: nil, defaults: defaults)
        let loaded = store.load()

        #expect(loaded.selectedLanguage == .korean)
        #expect(loaded.selectedModel == "base")

        defaults.removePersistentDomain(forName: suiteName)
    }
}
