import Foundation

/// Thread-safe ring buffer for 16kHz mono Float32 audio samples.
/// Capacity: 30 seconds = 480,000 samples ≈ 1.83 MB.
final class AudioBuffer: @unchecked Sendable {
    private let capacity: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var sampleCount: Int = 0
    private let lock = NSLock()

    init(capacity: Int = Constants.Audio.bufferSize) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Append samples to the ring buffer.
    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
        sampleCount = min(sampleCount + samples.count, capacity)
    }

    /// Read all buffered samples in chronological order.
    func read() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        guard sampleCount > 0 else { return [] }

        if sampleCount < capacity {
            // Buffer hasn't wrapped yet
            let startIndex = (writeIndex - sampleCount + capacity) % capacity
            if startIndex < writeIndex {
                return Array(buffer[startIndex..<writeIndex])
            } else {
                return Array(buffer[startIndex..<capacity]) + Array(buffer[0..<writeIndex])
            }
        } else {
            // Buffer is full, writeIndex is the oldest sample
            return Array(buffer[writeIndex..<capacity]) + Array(buffer[0..<writeIndex])
        }
    }

    /// Clear all buffered samples.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        writeIndex = 0
        sampleCount = 0
    }

    /// Number of samples currently in the buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return sampleCount
    }

    /// Duration of buffered audio in seconds.
    var duration: TimeInterval {
        Double(count) / Constants.Audio.sampleRate
    }
}
