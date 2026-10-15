import Foundation
import Testing
@testable import VoiceInput

@Suite("WhisperKit Model Loading Tests")
struct WhisperKitModelLoadingTests {
    private enum TestError: Error {
        case downloadCalled
    }

    @Test func modelCacheDoesNotRequireDocumentsPermission() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        #expect(WhisperKitModelStorage.modelsDirectory.path.hasPrefix(
            applicationSupport.path + "/"
        ))
    }

    @Test func findsDownloadedTurboModelFolder() throws {
        let fileManager = FileManager.default
        let modelsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let variant = Constants.Transcription.largeV3TurboModelVariant
        let expectedURL = modelsDirectory
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try fileManager.createDirectory(at: expectedURL, withIntermediateDirectories: true)
        for modelName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundleURL = expectedURL
                .appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
            try fileManager.createDirectory(
                at: bundleURL.appendingPathComponent("weights", isDirectory: true),
                withIntermediateDirectories: true
            )
            for payload in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                try Data([0]).write(to: bundleURL.appendingPathComponent(payload))
            }
        }
        defer { try? fileManager.removeItem(at: modelsDirectory) }

        let result = WhisperKitModelStorage.localModelURL(
            for: variant,
            in: modelsDirectory,
            fileManager: fileManager
        )

        #expect(result == expectedURL)
    }

    @Test func ignoresIncompleteModelFolder() throws {
        let fileManager = FileManager.default
        let modelsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let variant = Constants.Transcription.largeV3TurboModelVariant
        let incompleteURL = modelsDirectory
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        for modelName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try fileManager.createDirectory(
                at: incompleteURL.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        defer { try? fileManager.removeItem(at: modelsDirectory) }

        let result = WhisperKitModelStorage.localModelURL(
            for: variant,
            in: modelsDirectory,
            fileManager: fileManager
        )

        #expect(result == nil)
    }

    @Test func localModelSkipsDownload() async throws {
        let localURL = URL(fileURLWithPath: "/local/model")

        let result = try await WhisperKitEngine.resolveModelURL(localModelURL: localURL) {
            throw TestError.downloadCalled
        }

        #expect(result == localURL)
    }

    @Test func missingLocalModelUsesDownload() async throws {
        let downloadedURL = URL(fileURLWithPath: "/downloaded/model")

        let result = await WhisperKitEngine.resolveModelURL(localModelURL: nil) {
            downloadedURL
        }

        #expect(result == downloadedURL)
    }
}
