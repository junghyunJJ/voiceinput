import Foundation

/// Protocol for swappable speech-to-text backends.
/// Default implementation: WhisperKitEngine.
/// Can be swapped to SwiftWhisper (whisper.cpp) if needed.
protocol TranscriptionEngine: Actor {
    /// Whether the engine is ready to transcribe.
    var isReady: Bool { get }

    /// Load a model by variant name (e.g., "tiny", "base", "small", "large-v3").
    func loadModel(variant: String) async throws

    /// Unload the current model to free memory.
    func unloadModel() async

    /// Transcribe audio samples (16kHz mono Float32).
    func transcribe(
        audioSamples: [Float],
        language: String?
    ) async throws -> TranscriptionResult

    /// Detect the language of audio samples.
    func detectLanguage(audioSamples: [Float]) async throws -> String
}
