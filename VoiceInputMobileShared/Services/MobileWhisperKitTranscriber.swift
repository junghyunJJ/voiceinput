import Foundation
import WhisperKit

public struct MobileDictationResult: Sendable {
    public let text: String
    public let language: String

    public init(text: String, language: String) {
        self.text = text
        self.language = language
    }
}

public actor MobileWhisperKitTranscriber {
    private var whisperKit: WhisperKit?
    private var loadedModelVariant: String?

    public init() {}

    public func loadModelIfNeeded(variant: String) async throws {
        if loadedModelVariant == variant, whisperKit != nil {
            return
        }

        let modelURL = try await prepareModelAndRecoverIfNeeded(variant: variant)
        whisperKit = try await buildWhisperKit(using: modelURL, variant: variant, allowRecovery: true)
        loadedModelVariant = variant
    }

    public func transcribe(samples: [Float], language: String?) async throws -> MobileDictationResult {
        guard let whisperKit else {
            throw MobileWhisperKitTranscriberError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let language {
            options.language = language
        }

        let transcriptionResults: [TranscriptionResult]
        do {
            transcriptionResults = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        } catch {
            guard let loadedModelVariant, Self.shouldAttemptModelRecovery(for: error) else {
                throw error
            }

            let recoveredModelURL = try await recoverCorruptedModel(variant: loadedModelVariant)
            let recoveredWhisperKit = try await buildWhisperKit(
                using: recoveredModelURL,
                variant: loadedModelVariant,
                allowRecovery: false
            )
            self.whisperKit = recoveredWhisperKit
            transcriptionResults = try await recoveredWhisperKit.transcribe(audioArray: samples, decodeOptions: options)
        }

        guard let first = transcriptionResults.first else {
            throw MobileWhisperKitTranscriberError.noResult
        }

        let cleaned = first.text
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^\)]*\)|\*[^\*]+\*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MobileDictationResult(text: cleaned, language: first.language)
    }

    private func prepareModelAndRecoverIfNeeded(variant: String) async throws -> URL {
        let downloadedModelURL = try await Self.downloadModel(variant: variant)
        let missingFiles = Self.missingRequiredModelFiles(in: downloadedModelURL)
        guard missingFiles.isEmpty else {
            return try await recoverCorruptedModel(variant: variant)
        }

        return downloadedModelURL
    }

    private func recoverCorruptedModel(variant: String) async throws -> URL {
        try Self.purgeCachedModelFolders(variant: variant)
        let redownloadedModelURL = try await Self.downloadModel(variant: variant)
        let missingFilesAfterRecovery = Self.missingRequiredModelFiles(in: redownloadedModelURL)
        guard missingFilesAfterRecovery.isEmpty else {
            throw MobileWhisperKitTranscriberError.corruptedModelFiles(
                variant: variant,
                missingFiles: missingFilesAfterRecovery
            )
        }

        return redownloadedModelURL
    }

    private func buildWhisperKit(using modelURL: URL, variant: String, allowRecovery: Bool) async throws -> WhisperKit {
        let config = WhisperKitConfig(modelFolder: modelURL.path, load: true, download: false)
        do {
            return try await WhisperKit(config)
        } catch {
            guard allowRecovery, Self.shouldAttemptModelRecovery(for: error) else {
                throw error
            }

            let recoveredModelURL = try await recoverCorruptedModel(variant: variant)
            let recoveredConfig = WhisperKitConfig(modelFolder: recoveredModelURL.path, load: true, download: false)
            do {
                return try await WhisperKit(recoveredConfig)
            } catch {
                throw MobileWhisperKitTranscriberError.modelInitializationFailed(variant: variant)
            }
        }
    }

    private static func downloadModel(variant: String) async throws -> URL {
        let downloadBase = modelDownloadBase()
        try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)

        return try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            from: MobileConstants.Transcription.modelRepository,
            progressCallback: { _ in }
        )
    }

    static func missingRequiredModelFiles(in modelURL: URL, fileManager: FileManager = .default) -> [String] {
        // Text decoder files are mandatory across WhisperKit CoreML model variants.
        let requiredRelativePaths = [
            "TextDecoder.mlmodelc/model.mil",
            "TextDecoder.mlmodelc/weights/weight.bin",
        ]

        return requiredRelativePaths.filter { relativePath in
            !fileManager.fileExists(atPath: modelURL.appendingPathComponent(relativePath).path)
        }
    }

    private static func shouldAttemptModelRecovery(for error: Error) -> Bool {
        let description = collectedErrorText(error).lowercased()
        let indicators = [
            ".mlmodelc",
            "weight.bin",
            "could not open",
            "no such file",
            "error assigning ml model",
        ]

        return indicators.contains { description.contains($0) }
    }

    private static func collectedErrorText(_ error: Error) -> String {
        var values: [String] = []
        var currentError: NSError? = error as NSError
        var depth = 0

        while let nsError = currentError, depth < 6 {
            values.append(nsError.localizedDescription)
            if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                values.append(failureReason)
            }
            if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
                values.append(debugDescription)
            }
            currentError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        return values.joined(separator: " | ")
    }

    private static func purgeCachedModelFolders(variant: String, fileManager: FileManager = .default) throws {
        let repoPath = cachedModelRepositoryPath(fileManager: fileManager)
        guard fileManager.fileExists(atPath: repoPath.path) else {
            return
        }

        let entries = try fileManager.contentsOfDirectory(atPath: repoPath.path)
        for entry in entries where matchesModelVariant(entry, variant: variant) {
            try fileManager.removeItem(at: repoPath.appendingPathComponent(entry))
        }
    }

    static func cachedModelRepositoryPath(fileManager: FileManager = .default) -> URL {
        modelDownloadBase(fileManager: fileManager)
            .appendingPathComponent("huggingface/models")
            .appendingPathComponent(MobileConstants.Transcription.modelRepository)
    }

    static func matchesModelVariant(_ folderName: String, variant: String) -> Bool {
        folderName.hasSuffix("-\(variant)") ||
        folderName.hasSuffix("_\(variant)") ||
        folderName.hasSuffix("-\(variant.replacingOccurrences(of: "-", with: "_"))")
    }

    private static func modelDownloadBase(fileManager: FileManager = .default) -> URL {
        if let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: MobileConstants.appGroupIdentifier) {
            return shared.appendingPathComponent("VoiceInputModelCache", isDirectory: true)
        }

        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

public enum MobileWhisperKitTranscriberError: LocalizedError {
    case modelNotLoaded
    case noResult
    case corruptedModelFiles(variant: String, missingFiles: [String])
    case modelInitializationFailed(variant: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded."
        case .noResult:
            return "No transcription result produced."
        case let .corruptedModelFiles(variant, missingFiles):
            let missing = missingFiles.joined(separator: ", ")
            return "Model '\(variant)' files are incomplete (\(missing)). VoiceInput attempted re-download. Please keep network stable and try again."
        case let .modelInitializationFailed(variant):
            return "Model '\(variant)' could not be initialized after recovery. Restart the app and try again."
        }
    }
}
