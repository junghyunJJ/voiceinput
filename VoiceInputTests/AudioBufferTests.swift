import Testing
@testable import VoiceInput

@Suite("AudioBuffer Tests")
struct AudioBufferTests {

    @Test func writeAndRead() {
        let buffer = AudioBuffer(capacity: 10)
        buffer.write([1.0, 2.0, 3.0])

        let samples = buffer.read()
        #expect(samples == [1.0, 2.0, 3.0])
        #expect(buffer.count == 3)
    }

    @Test func ringBufferWraparound() {
        let buffer = AudioBuffer(capacity: 5)

        buffer.write([1.0, 2.0, 3.0])
        #expect(buffer.count == 3)

        // Write 4 more (total 7, capacity 5 → wraps)
        buffer.write([4.0, 5.0, 6.0, 7.0])
        #expect(buffer.count == 5)

        // Should contain the last 5 samples in order
        let samples = buffer.read()
        #expect(samples == [3.0, 4.0, 5.0, 6.0, 7.0])
    }

    @Test func reset() {
        let buffer = AudioBuffer(capacity: 10)
        buffer.write([1.0, 2.0, 3.0])
        buffer.reset()

        #expect(buffer.count == 0)
        #expect(buffer.read() == [])
    }

    @Test func emptyRead() {
        let buffer = AudioBuffer(capacity: 10)
        #expect(buffer.read() == [])
        #expect(buffer.count == 0)
    }

    @Test func exactCapacityFill() {
        let buffer = AudioBuffer(capacity: 4)
        buffer.write([1.0, 2.0, 3.0, 4.0])

        #expect(buffer.count == 4)
        #expect(buffer.read() == [1.0, 2.0, 3.0, 4.0])
    }

    @Test func duration() {
        let buffer = AudioBuffer(capacity: Int(Constants.Audio.sampleRate * 30))
        let oneSec = [Float](repeating: 0, count: Int(Constants.Audio.sampleRate))
        buffer.write(oneSec)

        #expect(abs(buffer.duration - 1.0) < 0.001)
    }

    @Test func multipleWraparounds() {
        let buffer = AudioBuffer(capacity: 3)

        buffer.write([1.0, 2.0, 3.0])
        buffer.write([4.0, 5.0])
        buffer.write([6.0, 7.0, 8.0])

        let samples = buffer.read()
        #expect(samples == [6.0, 7.0, 8.0])
    }
}
