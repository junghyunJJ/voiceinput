@preconcurrency import AVFoundation
import Dispatch
import Foundation

enum AudioCaptureStopReason: String, Sendable {
    case ok
    case notCapturing
    case noRawBuffersCaptured
    case engineConfigurationChanged
    case engineStoppedBeforeFirstTap
    case zeroFramesCaptured
    case conversionFailed
}

func classifyNoBufferStopReason(
    didReceiveTap: Bool,
    engineWasRunning: Bool,
    didObserveConfigurationChange: Bool
) -> AudioCaptureStopReason {
    if didObserveConfigurationChange {
        return .engineConfigurationChanged
    }
    if !didReceiveTap && !engineWasRunning {
        return .engineStoppedBeforeFirstTap
    }
    return .noRawBuffersCaptured
}

struct AudioCaptureResult: Sendable {
    let samples: [Float]
    let rawBufferCount: Int
    let totalFrames: Int
    let didReceiveTap: Bool
    let sourceSampleRate: Double?
    let stopReason: AudioCaptureStopReason
}

/// Thread-safe storage for audio buffers captured from the tap callback.
final class RawAudioStorage: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
    private var didReceiveTapBuffer = false
    private let lock = NSLock()

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    func drain() -> [AVAudioPCMBuffer] {
        lock.lock()
        let result = buffers
        buffers = []
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        buffers = []
        didReceiveTapBuffer = false
        lock.unlock()
    }

    func markTapReceived() {
        lock.lock()
        didReceiveTapBuffer = true
        lock.unlock()
    }

    var totalFrames: Int {
        lock.lock()
        let count = buffers.reduce(0) { $0 + Int($1.frameLength) }
        lock.unlock()
        return count
    }

    var sampleRate: Double? {
        lock.lock()
        let rate = buffers.first?.format.sampleRate
        lock.unlock()
        return rate
    }

    var didReceiveTap: Bool {
        lock.lock()
        let result = didReceiveTapBuffer
        lock.unlock()
        return result
    }
}

/// Thread-safe flags for capture lifecycle events.
final class AudioCaptureLifecycleFlags: @unchecked Sendable {
    private var observedConfigurationChange = false
    private let lock = NSLock()

    func reset() {
        lock.lock()
        observedConfigurationChange = false
        lock.unlock()
    }

    func markConfigurationChange() {
        lock.lock()
        observedConfigurationChange = true
        lock.unlock()
    }

    var didObserveConfigurationChange: Bool {
        lock.lock()
        let result = observedConfigurationChange
        lock.unlock()
        return result
    }
}

/// Actor that wraps AVAudioEngine for audio capture.
/// Captures in hardware format, then converts to 16kHz mono Float32 on stop.
actor AudioService {
    private var audioEngine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var hasInstalledTap = false
    private let rawStorage = RawAudioStorage()
    private let lifecycleFlags = AudioCaptureLifecycleFlags()
    private var isCapturing = false

    private let startupTapWaitNanoseconds: UInt64 = 350_000_000
    private let startupRetryDelayNanoseconds: UInt64 = 120_000_000
    private let maxStartupAttempts = 3

    /// Start capturing audio from the default input device.
    func startCapture() async throws {
        guard !isCapturing else { return }

        var lastStartupError: Error?

        for attempt in 1...maxStartupAttempts {
            rawStorage.reset()
            lifecycleFlags.reset()

            do {
                try setupCaptureEngine()
                let didReceiveInitialTap = await waitForInitialTap()
                if didReceiveInitialTap {
                    isCapturing = true
                    if attempt > 1 {
                        NSLog("[AudioService] Capture recovered on startup attempt %d/%d", attempt, maxStartupAttempts)
                    }
                    return
                }

                let engineRunning = audioEngine?.isRunning ?? false
                NSLog(
                    "[AudioService] Startup attempt %d/%d failed: tap=false engineRunning=%d configChanged=%d",
                    attempt,
                    maxStartupAttempts,
                    engineRunning ? 1 : 0,
                    lifecycleFlags.didObserveConfigurationChange ? 1 : 0
                )
                lastStartupError = AudioServiceError.captureStartupFailed
            } catch {
                NSLog("[AudioService] Startup attempt %d/%d error: %@", attempt, maxStartupAttempts, String(describing: error))
                lastStartupError = error
            }

            teardownCaptureEngine()

            if attempt < maxStartupAttempts {
                try? await Task.sleep(nanoseconds: startupRetryDelayNanoseconds)
            }
        }

        // Do not hard-fail recording start forever on unstable routes.
        // Fall back to best-effort capture and let stop-time diagnostics decide.
        do {
            rawStorage.reset()
            lifecycleFlags.reset()
            try setupCaptureEngine()
            isCapturing = true
            NSLog("[AudioService] Proceeding in best-effort capture mode after startup validation failures")
            return
        } catch {
            NSLog("[AudioService] Best-effort startup failed: %@", String(describing: error))
            throw lastStartupError ?? error
        }
    }

    /// Stop audio capture and return 16kHz mono Float32 samples plus diagnostics.
    func stopCapture() -> AudioCaptureResult {
        guard isCapturing else {
            NSLog("[AudioService] stopCapture: not capturing")
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: 0,
                totalFrames: 0,
                didReceiveTap: false,
                sourceSampleRate: nil,
                stopReason: .notCapturing
            )
        }

        let engineWasRunning = audioEngine?.isRunning ?? false
        let didObserveConfigurationChange = lifecycleFlags.didObserveConfigurationChange
        teardownCaptureEngine()

        let buffers = rawStorage.drain()
        let didReceiveTap = rawStorage.didReceiveTap
        NSLog("[AudioService] Drained %d raw buffers", buffers.count)

        guard !buffers.isEmpty, let sourceFormat = buffers.first?.format else {
            NSLog("[AudioService] No buffers captured!")
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: 0,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: nil,
                stopReason: classifyNoBufferStopReason(
                    didReceiveTap: didReceiveTap,
                    engineWasRunning: engineWasRunning,
                    didObserveConfigurationChange: didObserveConfigurationChange
                )
            )
        }

        // Concatenate all raw buffers into one
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        NSLog("[AudioService] Source format: %@, totalFrames: %d, duration: %.1fs", sourceFormat.description, totalFrames, Double(totalFrames) / sourceFormat.sampleRate)
        guard totalFrames > 0,
              let combined = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(totalFrames))
        else {
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: totalFrames,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: sourceFormat.sampleRate,
                stopReason: .zeroFramesCaptured
            )
        }

        combined.frameLength = AVAudioFrameCount(totalFrames)
        var offset = 0
        for buf in buffers {
            let len = Int(buf.frameLength)
            if let src = buf.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<Int(sourceFormat.channelCount) {
                    memcpy(dst[ch].advanced(by: offset), src[ch], len * MemoryLayout<Float>.size)
                }
            }
            offset += len
        }

        // Convert to 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: totalFrames,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: sourceFormat.sampleRate,
                stopReason: .conversionFailed
            )
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: totalFrames,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: sourceFormat.sampleRate,
                stopReason: .conversionFailed
            )
        }

        let ratio = Constants.Audio.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(totalFrames) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: totalFrames,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: sourceFormat.sampleRate,
                stopReason: .conversionFailed
            )
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return combined
        }

        guard error == nil, outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData else {
            return AudioCaptureResult(
                samples: [],
                rawBufferCount: buffers.count,
                totalFrames: totalFrames,
                didReceiveTap: didReceiveTap,
                sourceSampleRate: sourceFormat.sampleRate,
                stopReason: .conversionFailed
            )
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        return AudioCaptureResult(
            samples: samples,
            rawBufferCount: buffers.count,
            totalFrames: totalFrames,
            didReceiveTap: didReceiveTap,
            sourceSampleRate: sourceFormat.sampleRate,
            stopReason: .ok
        )
    }

    /// Current buffer duration in seconds.
    var bufferDuration: TimeInterval {
        guard let rate = rawStorage.sampleRate else { return 0 }
        return Double(rawStorage.totalFrames) / rate
    }

    private func setupCaptureEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        registerConfigurationObserver(for: engine)

        // Capture-only graph: avoid routing mic input to output mixer.
        // Output route reconfiguration can stop AVAudioEngine before tap buffers arrive.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: nil
        ) { [rawStorage] pcmBuffer, _ in
            rawStorage.markTapReceived()
            // Log first buffer to verify tap is firing.
            if rawStorage.totalFrames == 0 {
                NSLog("[AudioService] First tap callback! frames=%d format=%@", pcmBuffer.frameLength, pcmBuffer.format.description)
            }
            // Make a copy of the buffer since the original is reused.
            guard let copy = AVAudioPCMBuffer(pcmFormat: pcmBuffer.format, frameCapacity: pcmBuffer.frameLength) else { return }
            copy.frameLength = pcmBuffer.frameLength
            if let src = pcmBuffer.floatChannelData, let dst = copy.floatChannelData {
                for ch in 0..<Int(pcmBuffer.format.channelCount) {
                    memcpy(dst[ch], src[ch], Int(pcmBuffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            rawStorage.append(copy)
        }
        hasInstalledTap = true

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func waitForInitialTap() async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + startupTapWaitNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if rawStorage.didReceiveTap {
                return true
            }
            let engineRunning = audioEngine?.isRunning ?? false
            if !engineRunning && lifecycleFlags.didObserveConfigurationChange {
                return false
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let engineRunning = audioEngine?.isRunning ?? false
        if engineRunning && !lifecycleFlags.didObserveConfigurationChange {
            return true
        }
        return rawStorage.didReceiveTap
    }

    private func teardownCaptureEngine() {
        if let engine = audioEngine {
            if hasInstalledTap {
                engine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            engine.stop()
        } else {
            hasInstalledTap = false
        }
        audioEngine = nil
        isCapturing = false
        removeConfigurationObserver()
    }

    private func registerConfigurationObserver(for engine: AVAudioEngine) {
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [lifecycleFlags] _ in
            lifecycleFlags.markConfigurationChange()
            NSLog("[AudioService] AVAudioEngine configuration changed")
        }
    }

    private func removeConfigurationObserver() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
    }
}

enum AudioServiceError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case captureStartupFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create target audio format (16kHz mono)."
        case .converterCreationFailed:
            return "Failed to create audio format converter."
        case .captureStartupFailed:
            return "Failed to start microphone capture after retries."
        }
    }
}
