import Foundation
import WhisperKit

enum WhisperKitModelStorage {
    static var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models")
            .appendingPathComponent(Constants.Transcription.modelRepository)
    }

    static func localModelURL(for variant: String) -> URL? {
        localModelURL(for: variant, in: modelsDirectory)
    }

    static func localModelURL(
        for variant: String,
        in modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let contents = (try? fileManager.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
        guard let folder = findModelFolder(for: variant, in: contents) else { return nil }
        let modelURL = modelsDirectory.appendingPathComponent(folder, isDirectory: true)
        let requiredModels = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        guard requiredModels.allSatisfy({ modelName in
            let compiled = modelURL.appendingPathComponent("\(modelName).mlmodelc")
            let compiledPayloads = ["coremldata.bin", "model.mil", "weights/weight.bin"]
            let compiledModelExists = compiledPayloads.allSatisfy { payload in
                fileManager.fileExists(atPath: compiled.appendingPathComponent(payload).path)
            }
            let package = modelURL.appendingPathComponent(
                "\(modelName).mlpackage/Data/com.apple.CoreML/model.mlmodel"
            )
            return compiledModelExists ||
                fileManager.fileExists(atPath: package.path)
        }) else { return nil }
        return modelURL
    }

    static func findModelFolder(for variant: String, in contents: [String]) -> String? {
        contents.first { folder in
            folder.hasSuffix("-\(variant)") ||
            folder.hasSuffix("_\(variant)") ||
            folder.hasSuffix("-\(variant.replacingOccurrences(of: "-", with: "_"))")
        }
    }
}

/// Manages WhisperKit model downloads, caching, and selection.
@MainActor
@Observable
final class ModelManager {
    var availableModels: [ModelInfo] = []
    var downloadProgress: Double = 0
    var isDownloading = false
    var downloadingModel: String?

    struct ModelInfo: Identifiable {
        let variant: String
        let displayName: String
        let sizeDescription: String
        let isDownloaded: Bool

        var id: String { variant }
    }

    private static let modelCatalog: [(variant: String, display: String, size: String)] = [
        ("tiny", "Tiny", "~75 MB"),
        ("base", "Base", "~145 MB"),
        ("small", "Small", "~465 MB"),
        ("medium", "Medium", "~1.5 GB"),
        ("large-v3", "Large v3", "~3.0 GB"),
        (Constants.Transcription.largeV3TurboModelVariant, "Large v3 Turbo", "~632 MB"),
    ]

    var downloadProgressClamped: Double {
        min(max(downloadProgress, 0), 1)
    }

    var downloadProgressPercentText: String {
        "\(Int((downloadProgressClamped * 100).rounded()))%"
    }

    var downloadingModelDisplayName: String {
        guard let downloadingModel else { return "Model" }
        return Self.modelCatalog.first { $0.variant == downloadingModel }?.display ?? downloadingModel
    }

    init() {
        refreshAvailableModels()
        NotificationCenter.default.addObserver(
            forName: .modelDownloadProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let progress = notification.userInfo?["progress"] as? Double {
                    self?.downloadProgress = progress
                }
            }
        }
    }

    func refreshAvailableModels() {
        let fm = FileManager.default
        let modelsDir = WhisperKitModelStorage.modelsDirectory

        availableModels = Self.modelCatalog.map { model in
            let downloaded = WhisperKitModelStorage.localModelURL(
                for: model.variant,
                in: modelsDir,
                fileManager: fm
            ) != nil
            return ModelInfo(
                variant: model.variant,
                displayName: model.display,
                sizeDescription: model.size,
                isDownloaded: downloaded
            )
        }
    }

    func downloadModel(variant: String) async throws {
        isDownloading = true
        downloadingModel = variant
        downloadProgress = 0

        defer {
            isDownloading = false
            downloadingModel = nil
            refreshAvailableModels()
        }

        _ = try await WhisperKit.download(
            variant: variant,
            from: Constants.Transcription.modelRepository,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
        )
    }

    func deleteModel(variant: String) throws {
        let fm = FileManager.default
        let modelsDir = WhisperKitModelStorage.modelsDirectory
        let contents = (try? fm.contentsOfDirectory(atPath: modelsDir.path)) ?? []
        if let folder = WhisperKitModelStorage.findModelFolder(for: variant, in: contents) {
            let folderPath = modelsDir.appendingPathComponent(folder)
            try fm.removeItem(at: folderPath)
        }
        refreshAvailableModels()
    }

    func modelSize(variant: String) -> String {
        Self.modelCatalog.first { $0.variant == variant }?.size ?? "Unknown"
    }

    var isLargeModelWarningNeeded: Bool {
        // Warn on 8GB machines before loading large models
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        return totalMemory <= eightGB
    }
}
