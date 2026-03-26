@preconcurrency import AVFoundation
import Foundation

public struct MobileAudioCaptureResult: Sendable {
    public let samples: [Float]
    public let sourceSampleRate: Double?

    public init(samples: [Float], sourceSampleRate: Double?) {
        self.samples = samples
        self.sourceSampleRate = sourceSampleRate
    }
}

final class MobileRawAudioStorage: @unchecked Sendable {
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
}

public actor MobileAudioCaptureService {
    private enum CaptureBackend {
        case engine
        case recorder
    }

    private struct SessionCandidate {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private let rawStorage = MobileRawAudioStorage()
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var recorderFileURL: URL?
    private var captureBackend: CaptureBackend?
    private var hasInstalledTap = false
    private var isCapturing = false

    public init() {}

    public func startCapture() async throws {
        guard !isCapturing else { return }

        let session = AVAudioSession.sharedInstance()
        try configureAudioSession(session)

        rawStorage.reset()
        let isExtensionProcess = Bundle.main.bundleURL.pathExtension == "appex"

        do {
            try startEngineCapture()
            captureBackend = .engine
            isCapturing = true
        } catch {
            guard isExtensionProcess else {
                throw error
            }

            stopEngineCaptureStateOnly()
            do {
                try startRecorderCapture()
                captureBackend = .recorder
                isCapturing = true
            } catch {
                throw NSError(
                    domain: "VoiceInput.AudioCapture",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Unable to start audio capture in keyboard extension.",
                        NSUnderlyingErrorKey: error,
                    ]
                )
            }
        }
    }

    public func stopCapture() async -> MobileAudioCaptureResult {
        guard isCapturing else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: nil)
        }

        let result: MobileAudioCaptureResult
        switch captureBackend {
        case .engine:
            result = stopEngineCapture()
        case .recorder:
            result = stopRecorderCapture()
        case .none:
            result = MobileAudioCaptureResult(samples: [], sourceSampleRate: nil)
        }

        captureBackend = nil
        isCapturing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return result
    }

    private func startEngineCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [rawStorage] pcmBuffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: pcmBuffer.format, frameCapacity: pcmBuffer.frameLength) else {
                return
            }
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

    private func stopEngineCaptureStateOnly() {
        if hasInstalledTap {
            audioEngine?.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        audioEngine?.stop()
        audioEngine = nil
    }

    private func stopEngineCapture() -> MobileAudioCaptureResult {
        stopEngineCaptureStateOnly()

        let buffers = rawStorage.drain()
        guard !buffers.isEmpty, let sourceFormat = buffers.first?.format else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: nil)
        }

        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0,
              let combined = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(totalFrames))
        else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: sourceFormat.sampleRate)
        }

        combined.frameLength = AVAudioFrameCount(totalFrames)
        var offset = 0
        for buffer in buffers {
            let length = Int(buffer.frameLength)
            if let src = buffer.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<Int(sourceFormat.channelCount) {
                    memcpy(dst[ch].advanced(by: offset), src[ch], length * MemoryLayout<Float>.size)
                }
            }
            offset += length
        }

        return convertToTargetSamples(from: combined)
    }

    private func startRecorderCapture() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("VoiceInputKeyboardCapture", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("capture-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: MobileConstants.Audio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw NSError(
                domain: "VoiceInput.AudioCapture",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder failed to start."]
            )
        }

        audioRecorder = recorder
        recorderFileURL = fileURL
    }

    private func stopRecorderCapture() -> MobileAudioCaptureResult {
        audioRecorder?.stop()
        audioRecorder = nil

        guard let fileURL = recorderFileURL else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: nil)
        }
        recorderFileURL = nil

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        guard let file = try? AVAudioFile(forReading: fileURL) else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: nil)
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: format.sampleRate)
        }

        do {
            try file.read(into: buffer)
        } catch {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: format.sampleRate)
        }

        return convertToTargetSamples(from: buffer)
    }

    private func convertToTargetSamples(from sourceBuffer: AVAudioPCMBuffer) -> MobileAudioCaptureResult {
        let sourceFormat = sourceBuffer.format
        guard sourceBuffer.frameLength > 0 else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: sourceFormat.sampleRate)
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: MobileConstants.Audio.sampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: sourceFormat.sampleRate)
        }

        let ratio = MobileConstants.Audio.sampleRate / sourceFormat.sampleRate
        let estimatedFrameCount = max(AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 128, 2048)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrameCount) else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: sourceFormat.sampleRate)
        }

        var hasProvidedInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard conversionError == nil,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData
        else {
            return MobileAudioCaptureResult(samples: [], sourceSampleRate: sourceFormat.sampleRate)
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        return MobileAudioCaptureResult(samples: samples, sourceSampleRate: sourceFormat.sampleRate)
    }

    private func configureAudioSession(_ session: AVAudioSession) throws {
        let isExtensionProcess = Bundle.main.bundleURL.pathExtension == "appex"
        let candidates: [SessionCandidate]

        if isExtensionProcess {
            candidates = [
                SessionCandidate(category: .playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP]),
                SessionCandidate(category: .record, mode: .default, options: []),
                SessionCandidate(category: .playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP]),
            ]
        } else {
            candidates = [
                SessionCandidate(category: .playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]),
            ]
        }

        try? session.setPreferredSampleRate(MobileConstants.Audio.sampleRate)
        try? session.setPreferredIOBufferDuration(0.005)

        var lastError: Error?
        for candidate in candidates {
            do {
                try session.setCategory(candidate.category, mode: candidate.mode, options: candidate.options)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                return
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "VoiceInput.AudioSession",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to activate audio session."]
        )
    }
}
