import Testing
@testable import VoiceInput

@Suite("Audio Capture Stop Reason Tests")
struct AudioCaptureStopReasonTests {

    @Test func classifiesConfigurationChangeAsPrimaryReason() {
        let reason = classifyNoBufferStopReason(
            didReceiveTap: false,
            engineWasRunning: false,
            didObserveConfigurationChange: true
        )
        #expect(reason == .engineConfigurationChanged)
    }

    @Test func classifiesEngineStoppedBeforeTap() {
        let reason = classifyNoBufferStopReason(
            didReceiveTap: false,
            engineWasRunning: false,
            didObserveConfigurationChange: false
        )
        #expect(reason == .engineStoppedBeforeFirstTap)
    }

    @Test func fallsBackToNoRawBuffersCapturedWhenEngineStillRunning() {
        let reason = classifyNoBufferStopReason(
            didReceiveTap: false,
            engineWasRunning: true,
            didObserveConfigurationChange: false
        )
        #expect(reason == .noRawBuffersCaptured)
    }

    @Test func doesNotUseStoppedBeforeTapWhenTapWasSeen() {
        let reason = classifyNoBufferStopReason(
            didReceiveTap: true,
            engineWasRunning: false,
            didObserveConfigurationChange: false
        )
        #expect(reason == .noRawBuffersCaptured)
    }
}
