import AVFoundation
import Foundation
import Testing
@testable import VoiceInput

@Suite("Audio Diagnostics Tests", .serialized)
struct AudioDiagnosticsTests {
    @Test func rejectsSilence() {
        let metrics = AudioDiagnostics.analyze(
            samples: Array(repeating: 0, count: 4_800)
        )

        #expect(metrics.rms == 0)
        #expect(metrics.peak == 0)
        #expect(metrics.activeFrameCount == 0)
        #expect(!metrics.containsSpeech)
    }

    @Test func acceptsOneActiveHundredMillisecondFrame() {
        let metrics = AudioDiagnostics.analyze(
            samples: Array(repeating: 0.03, count: 1_600)
        )

        #expect(metrics.activeFrameCount == 1)
        #expect(metrics.totalFrameCount == 1)
        #expect(metrics.containsSpeech)
    }

    @Test func rejectsSignalBelowTheEnergyThreshold() {
        let metrics = AudioDiagnostics.analyze(
            samples: Array(repeating: 0.019, count: 4_800)
        )

        #expect(metrics.activeFrameCount == 0)
        #expect(!metrics.containsSpeech)
    }

    @Test func writesA16kMonoFloatFixture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("fixture.wav")
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples: [Float] = [0.0, 0.25, -0.25, 0.0]
        try AudioDiagnostics.writeFixture(samples: samples, to: url)

        let file = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        #expect(file.fileFormat.sampleRate == Constants.Audio.sampleRate)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length == AVAudioFramePosition(samples.count))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}
