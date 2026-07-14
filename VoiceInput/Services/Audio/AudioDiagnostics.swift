import AVFoundation
import Foundation
import WhisperKit

struct AudioSignalMetrics: Equatable, Sendable {
    let rms: Float
    let peak: Float
    let activeFrameCount: Int
    let totalFrameCount: Int

    var activeFrameRatio: Float {
        guard totalFrameCount > 0 else { return 0 }
        return Float(activeFrameCount) / Float(totalFrameCount)
    }

    var containsSpeech: Bool {
        activeFrameCount >= AudioDiagnostics.minimumSpeechFrameCount
    }

    var logSummary: String {
        String(
            format: "rms=%.5f peak=%.5f activeFrames=%d/%d activeRatio=%.3f",
            rms,
            peak,
            activeFrameCount,
            totalFrameCount,
            activeFrameRatio
        )
    }
}

enum AudioDiagnostics {
    static let fixtureEnvironmentVariable = "VOICEINPUT_EMPTY_TRANSCRIPTION_FIXTURE"
    static let frameLengthSamples = 1_600
    static let energyThreshold: Float = 0.02
    static let minimumSpeechFrameCount = 1

    static func analyze(samples: [Float]) -> AudioSignalMetrics {
        guard !samples.isEmpty else {
            return AudioSignalMetrics(
                rms: 0,
                peak: 0,
                activeFrameCount: 0,
                totalFrameCount: 0
            )
        }

        let energy = AudioProcessor.calculateEnergy(of: samples)
        let frameCount = Int(
            ceil(Double(samples.count) / Double(frameLengthSamples))
        )
        let activity = AudioProcessor.calculateVoiceActivityInChunks(
            of: samples,
            chunkCount: frameCount,
            frameLengthSamples: frameLengthSamples,
            energyThreshold: energyThreshold
        )

        return AudioSignalMetrics(
            rms: energy.avg,
            peak: energy.max,
            activeFrameCount: activity.filter { $0 }.count,
            totalFrameCount: activity.count
        )
    }

    static func writeEmptyFixtureIfRequested(samples: [Float]) throws -> URL? {
        guard
            let path = ProcessInfo.processInfo.environment[fixtureEnvironmentVariable],
            !path.isEmpty
        else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        try writeFixture(samples: samples, to: url)
        return url
    }

    static func writeFixture(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioDiagnosticsError.couldNotCreateFormat
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw AudioDiagnosticsError.couldNotCreateBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let destination = buffer.floatChannelData?.pointee {
            samples.withUnsafeBufferPointer { source in
                guard let sourceAddress = source.baseAddress else { return }
                destination.update(from: sourceAddress, count: source.count)
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try file.write(from: buffer)
    }
}

enum AudioDiagnosticsError: Error {
    case couldNotCreateFormat
    case couldNotCreateBuffer
}
