import Foundation
import WhisperKit

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
        ("large-v3-turbo", "Large v3 Turbo", "~800 MB"),
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

    /// HuggingFace default download directory (where WhisperKit actually stores models).
    private static var huggingFaceModelsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models")
            .appendingPathComponent(Constants.Transcription.modelRepository)
    }

    /// Find the actual folder name for a variant (e.g., "medium" → "openai_whisper-medium").
    private static func findModelFolder(for variant: String, in contents: [String]) -> String? {
        contents.first { folder in
            folder.hasSuffix("-\(variant)") ||
            folder.hasSuffix("_\(variant)") ||
            folder.hasSuffix("-\(variant.replacingOccurrences(of: "-", with: "_"))")
        }
    }

    func refreshAvailableModels() {
        let fm = FileManager.default
        let modelsDir = Self.huggingFaceModelsDir
        let contents = (try? fm.contentsOfDirectory(atPath: modelsDir.path)) ?? []

        availableModels = Self.modelCatalog.map { model in
            let downloaded = Self.findModelFolder(for: model.variant, in: contents) != nil
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
        let modelsDir = Self.huggingFaceModelsDir
        let contents = (try? fm.contentsOfDirectory(atPath: modelsDir.path)) ?? []
        if let folder = Self.findModelFolder(for: variant, in: contents) {
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
