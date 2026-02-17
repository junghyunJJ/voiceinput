@preconcurrency import AVFoundation
import Foundation

/// Thread-safe storage for audio buffers captured from the tap callback.
final class RawAudioStorage: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
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
}

/// Actor that wraps AVAudioEngine for audio capture.
/// Captures in hardware format, then converts to 16kHz mono Float32 on stop.
actor AudioService {
    private var audioEngine: AVAudioEngine?
    private let rawStorage = RawAudioStorage()
    private var isCapturing = false

    /// Start capturing audio from the default input device.
    func startCapture() throws {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        rawStorage.reset()

        // Connect input to output so audio flows through the graph.
        // Mute the output to prevent microphone feedback.
        engine.connect(inputNode, to: engine.mainMixerNode, format: hardwareFormat)
        engine.mainMixerNode.outputVolume = 0

        // Capture in hardware format — no conversion during recording
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: hardwareFormat
        ) { [rawStorage] pcmBuffer, _ in
            // Log first buffer to verify tap is firing
            if rawStorage.totalFrames == 0 {
                NSLog("[AudioService] First tap callback! frames=%d format=%@", pcmBuffer.frameLength, pcmBuffer.format.description)
            }
            // Make a copy of the buffer since the original is reused
            guard let copy = AVAudioPCMBuffer(pcmFormat: pcmBuffer.format, frameCapacity: pcmBuffer.frameLength) else { return }
            copy.frameLength = pcmBuffer.frameLength
            if let src = pcmBuffer.floatChannelData, let dst = copy.floatChannelData {
                for ch in 0..<Int(pcmBuffer.format.channelCount) {
                    memcpy(dst[ch], src[ch], Int(pcmBuffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            rawStorage.append(copy)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.isCapturing = true
    }

    /// Stop audio capture and return 16kHz mono Float32 samples.
    func stopCapture() -> [Float] {
        guard isCapturing else {
            NSLog("[AudioService] stopCapture: not capturing")
            return []
        }

        NSLog("[AudioService] Removing tap and stopping engine...")
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false

        let buffers = rawStorage.drain()
        NSLog("[AudioService] Drained %d raw buffers", buffers.count)

        guard !buffers.isEmpty, let sourceFormat = buffers.first?.format else {
            NSLog("[AudioService] No buffers captured!")
            return []
        }

        // Concatenate all raw buffers into one
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        NSLog("[AudioService] Source format: %@, totalFrames: %d, duration: %.1fs", sourceFormat.description, totalFrames, Double(totalFrames) / sourceFormat.sampleRate)
        guard totalFrames > 0,
              let combined = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(totalFrames))
        else { return [] }

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
        ) else { return [] }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return [] }

        let ratio = Constants.Audio.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(totalFrames) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return [] }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return combined
        }

        guard error == nil, outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData else { return [] }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    /// Current buffer duration in seconds.
    var bufferDuration: TimeInterval {
        guard let rate = rawStorage.sampleRate else { return 0 }
        return Double(rawStorage.totalFrames) / rate
    }
}

enum AudioServiceError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create target audio format (16kHz mono)."
        case .converterCreationFailed:
            return "Failed to create audio format converter."
        }
    }
}
