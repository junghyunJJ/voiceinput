import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import VoiceInput

private let emptyTranscriptionFixturePath =
    ProcessInfo.processInfo.environment[AudioDiagnostics.fixtureEnvironmentVariable]
private let emptyTranscriptionFixtureSHA256 =
    "a618dd83c332c8d8a6aa7ee82d6a950cb4c65fc274f3c8c95cc4bcf922fbf50e"

@Suite("Empty Transcription Regression Tests", .serialized)
struct EmptyTranscriptionRegressionTests {
    @Test(
        "captured speech produces text ten times",
        .enabled(if: emptyTranscriptionFixturePath != nil)
    )
    func capturedFailureProducesText() async throws {
        let path = try #require(emptyTranscriptionFixturePath)
        let fixtureURL = URL(fileURLWithPath: path)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixtureSHA256 = SHA256.hash(data: fixtureData)
            .map { String(format: "%02x", $0) }
            .joined()
        try #require(fixtureSHA256 == emptyTranscriptionFixtureSHA256)

        let samples = try loadSamples(from: fixtureURL)
        let metrics = AudioDiagnostics.analyze(samples: samples)
        try #require(metrics.containsSpeech)

        let engine = WhisperKitEngine()
        try await engine.loadModel(
            variant: Constants.Transcription.largeV3TurboModelVariant
        )

        var emptyIterations: [Int] = []
        for iteration in 1...10 {
            let result = try await engine.transcribe(
                audioSamples: samples,
                language: "ko"
            )
            if result.text.isEmpty {
                emptyIterations.append(iteration)
            }
        }

        #expect(emptyIterations.isEmpty)
    }

    private func loadSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioDiagnosticsError.couldNotCreateBuffer
        }

        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw AudioDiagnosticsError.couldNotCreateBuffer
        }

        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        )
    }
}
