import Foundation
import WhisperKit

/// WhisperKit-based transcription engine.
/// Native Swift, Apple Silicon optimized, built-in VAD.
actor WhisperKitEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?

    var isReady: Bool {
        whisperKit != nil
    }

    func loadModel(variant: String) async throws {
        // Download model if needed
        let modelURL = try await WhisperKit.download(
            variant: variant,
            from: Constants.Transcription.modelRepository,
            progressCallback: { progress in
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .modelDownloadProgress,
                        object: nil,
                        userInfo: ["progress": progress.fractionCompleted]
                    )
                }
            }
        )

        // Initialize WhisperKit with the downloaded model
        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func unloadModel() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
    }

    func transcribe(
        audioSamples: [Float],
        language: String?
    ) async throws -> TranscriptionResult {
        guard let pipe = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let startTime = Date()

        var options = DecodingOptions()
        if let language, language != "auto" {
            options.language = language
        }

        let results = try await pipe.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        guard let result = results.first else {
            throw TranscriptionError.noResult
        }

        let duration = Date().timeIntervalSince(startTime)

        let segments = result.segments.map { segment in
            TranscriptionResult.Segment(
                text: segment.text,
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end)
            )
        }

        // Filter out WhisperKit hallucination/meta tokens
        var cleanText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove bracketed/parenthesized meta tokens like [BLANK_AUDIO], [끝], [Sigh], [inaudible], *Sing*, (끝)
        cleanText = cleanText.replacingOccurrences(
            of: #"\[[^\]]*\]|\([^\)]*\)|\*[^\*]+\*"#,
            with: "",
            options: .regularExpression
        )
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        return TranscriptionResult(
            text: cleanText,
            language: result.language,
            segments: segments,
            duration: duration
        )
    }

    func detectLanguage(audioSamples: [Float]) async throws -> String {
        // Use transcribe with no language hint — WhisperKit auto-detects
        let result = try await transcribe(audioSamples: audioSamples, language: nil)
        return result.language
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case noResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded. Please download a model first."
        case .noResult:
            return "No transcription result was produced."
        }
    }
}

extension Notification.Name {
    static let modelDownloadProgress = Notification.Name("modelDownloadProgress")
}
