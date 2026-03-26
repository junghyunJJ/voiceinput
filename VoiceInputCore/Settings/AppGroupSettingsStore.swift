import Foundation

public enum SharedSettingsStoreKey {
    public static let settingsBlob = "voiceinput.sharedSettings.v1"

    // Legacy/override keys for partial migration and emergency recovery.
    public static let selectedLanguage = "selectedLanguage"
    public static let selectedModel = "selectedModel"
    public static let recordingMode = "recordingMode"
    public static let hotkeyMode = "hotkeyMode"
    public static let autoInsertText = "autoInsertText"
    public static let glossary = "transcriptionGlossary"
    public static let corrections = "transcriptionCorrections"
    public static let candidateCorrections = "transcriptionCandidateCorrections"
    public static let outputPreset = "outputPreset"
}

public enum AppGroupValidationPolicy: Sendable {
    case allowStandardFallback
    case requireAppGroup
}

public enum AppGroupSettingsStoreError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case invalidAppGroupIdentifier(String)
    case appGroupStoreUnavailable(String)
}

public enum AppGroupStorageLocation: Equatable, Sendable {
    case injectedDefaults
    case appGroup(String)
    case standardFallback(requestedGroup: String?)
}

public final class AppGroupSettingsStore {
    public let appGroupIdentifier: String?
    public let storageLocation: AppGroupStorageLocation

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        appGroupIdentifier: String?,
        validationPolicy: AppGroupValidationPolicy = .allowStandardFallback,
        defaults: UserDefaults? = nil
    ) throws {
        self.appGroupIdentifier = appGroupIdentifier

        if let defaults {
            self.defaults = defaults
            self.storageLocation = .injectedDefaults
            return
        }

        guard let appGroupIdentifier else {
            if validationPolicy == .requireAppGroup {
                throw AppGroupSettingsStoreError.missingAppGroupIdentifier
            }
            self.defaults = .standard
            self.storageLocation = .standardFallback(requestedGroup: nil)
            return
        }

        guard Self.isLikelyAppGroupIdentifier(appGroupIdentifier) else {
            if validationPolicy == .requireAppGroup {
                throw AppGroupSettingsStoreError.invalidAppGroupIdentifier(appGroupIdentifier)
            }
            self.defaults = .standard
            self.storageLocation = .standardFallback(requestedGroup: appGroupIdentifier)
            return
        }

        guard let suiteDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            if validationPolicy == .requireAppGroup {
                throw AppGroupSettingsStoreError.appGroupStoreUnavailable(appGroupIdentifier)
            }
            self.defaults = .standard
            self.storageLocation = .standardFallback(requestedGroup: appGroupIdentifier)
            return
        }

        self.defaults = suiteDefaults
        self.storageLocation = .appGroup(appGroupIdentifier)
    }

    private static func isLikelyAppGroupIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("group.") && identifier.count > "group.".count
    }

    public var isUsingFallbackStore: Bool {
        if case .standardFallback = storageLocation {
            return true
        }
        return false
    }

    public var isUsingAppGroupStore: Bool {
        if case .appGroup = storageLocation {
            return true
        }
        return false
    }

    public var isUsingInjectedStore: Bool {
        if case .injectedDefaults = storageLocation {
            return true
        }
        return false
    }

    private func loadRecordingMode() -> RecordingMode {
        if let rawMode = defaults.string(forKey: SharedSettingsStoreKey.recordingMode),
           let mode = RecordingMode(rawValue: rawMode) {
            return mode
        }

        if let legacyRawMode = defaults.string(forKey: SharedSettingsStoreKey.hotkeyMode),
           let mode = RecordingMode(rawValue: legacyRawMode) {
            return mode
        }

        return .toggle
    }

    public func load() -> SharedSettings {
        if let data = defaults.data(forKey: SharedSettingsStoreKey.settingsBlob),
           let decoded = try? decoder.decode(SharedSettings.self, from: data) {
            return decoded.sanitizedForPersistence
        }

        // Fallback to selected legacy keys so existing settings survive early migration.
        var migrated = SharedSettings.default

        if let rawLanguage = defaults.string(forKey: SharedSettingsStoreKey.selectedLanguage),
           let language = DictationLanguage(rawValue: rawLanguage) {
            migrated.selectedLanguage = language
        }

        if let selectedModel = defaults.string(forKey: SharedSettingsStoreKey.selectedModel),
           !selectedModel.isEmpty {
            migrated.selectedModel = selectedModel
        }

        migrated.recordingMode = loadRecordingMode()

        if defaults.object(forKey: SharedSettingsStoreKey.autoInsertText) != nil {
            migrated.autoInsertText = defaults.bool(forKey: SharedSettingsStoreKey.autoInsertText)
        }

        if let glossaryData = defaults.data(forKey: SharedSettingsStoreKey.glossary),
           let glossary = try? decoder.decode([TranscriptionGlossaryItem].self, from: glossaryData) {
            migrated.glossary = glossary.normalizedForPersistence
        }

        if let correctionsData = defaults.data(forKey: SharedSettingsStoreKey.corrections),
           let corrections = try? decoder.decode([TranscriptionCorrectionRule].self, from: correctionsData) {
            migrated.corrections = corrections.normalizedForPersistence
        }

        if let candidateCorrectionsData = defaults.data(forKey: SharedSettingsStoreKey.candidateCorrections),
           let candidateCorrections = try? decoder.decode([TranscriptionCandidateCorrectionRule].self, from: candidateCorrectionsData) {
            migrated.candidateCorrections = candidateCorrections.normalizedForEvaluation
        }

        if let rawPreset = defaults.string(forKey: SharedSettingsStoreKey.outputPreset),
           let preset = TranscriptionOutputPreset(rawValue: rawPreset) {
            migrated.outputPreset = preset
        }

        return migrated.sanitizedForPersistence
    }

    public func save(_ settings: SharedSettings) {
        let normalized = settings.sanitizedForPersistence

        if let data = try? encoder.encode(normalized) {
            defaults.set(data, forKey: SharedSettingsStoreKey.settingsBlob)
        }

        // Keep critical keys mirrored for compatibility with pre-core settings readers.
        defaults.set(normalized.selectedLanguage.rawValue, forKey: SharedSettingsStoreKey.selectedLanguage)
        defaults.set(normalized.selectedModel, forKey: SharedSettingsStoreKey.selectedModel)
        defaults.set(normalized.recordingMode.rawValue, forKey: SharedSettingsStoreKey.recordingMode)
        defaults.set(normalized.recordingMode.rawValue, forKey: SharedSettingsStoreKey.hotkeyMode)
        defaults.set(normalized.autoInsertText, forKey: SharedSettingsStoreKey.autoInsertText)
        defaults.set(normalized.outputPreset.rawValue, forKey: SharedSettingsStoreKey.outputPreset)
        if let glossaryData = try? encoder.encode(normalized.glossary) {
            defaults.set(glossaryData, forKey: SharedSettingsStoreKey.glossary)
        }
        if let correctionsData = try? encoder.encode(normalized.corrections) {
            defaults.set(correctionsData, forKey: SharedSettingsStoreKey.corrections)
        }
        if let candidateCorrectionsData = try? encoder.encode(normalized.candidateCorrections) {
            defaults.set(candidateCorrectionsData, forKey: SharedSettingsStoreKey.candidateCorrections)
        }
    }

    public func update(_ body: (inout SharedSettings) -> Void) {
        var settings = load()
        body(&settings)
        save(settings)
    }

    public func resetForTesting() {
        defaults.removeObject(forKey: SharedSettingsStoreKey.settingsBlob)
        defaults.removeObject(forKey: SharedSettingsStoreKey.selectedLanguage)
        defaults.removeObject(forKey: SharedSettingsStoreKey.selectedModel)
        defaults.removeObject(forKey: SharedSettingsStoreKey.recordingMode)
        defaults.removeObject(forKey: SharedSettingsStoreKey.hotkeyMode)
        defaults.removeObject(forKey: SharedSettingsStoreKey.autoInsertText)
        defaults.removeObject(forKey: SharedSettingsStoreKey.glossary)
        defaults.removeObject(forKey: SharedSettingsStoreKey.corrections)
        defaults.removeObject(forKey: SharedSettingsStoreKey.candidateCorrections)
        defaults.removeObject(forKey: SharedSettingsStoreKey.outputPreset)
    }
}
