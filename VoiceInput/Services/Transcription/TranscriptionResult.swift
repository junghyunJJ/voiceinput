import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let language: String
    let segments: [Segment]
    let duration: TimeInterval

    struct Segment: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
}
