import Testing
@testable import KaptureKit

@Suite("CaptureSequence")
struct CaptureSequenceTests {
    @Test("defaults to four shots on a three-second countdown")
    func defaults() {
        let sequence = CaptureSequence.standard
        #expect(sequence.frameCount == 4)
        #expect(sequence.countdownSeconds == 3)
    }

    @Test("excludes the trailing review from total duration")
    func duration() {
        let sequence = CaptureSequence(frameCount: 4, countdownSeconds: 3, reviewSeconds: 1)
        #expect(sequence.totalDuration == 15)
    }

    @Test("a single shot is just its countdown")
    func singleShot() {
        let sequence = CaptureSequence(frameCount: 1, countdownSeconds: 3, reviewSeconds: 1)
        #expect(sequence.totalDuration == 3)
    }
}
