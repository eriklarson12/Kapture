import Foundation
import Testing
@testable import KaptureKit

/// A clock that never sleeps but records everything it was asked to wait for.
/// That turns the timing plan into something a test can assert, instead of
/// something a test can only sit through.
@MainActor
final class TestClock: CaptureClock {
    private(set) var waits: [Duration] = []
    /// Called after each wait is recorded, with the running count. The cancel
    /// test uses it to interrupt a run partway through.
    var onWait: ((Int) -> Void)?

    func wait(_ duration: Duration) async {
        waits.append(duration)
        onWait?(waits.count)
    }
}

@Suite("CaptureRunner")
@MainActor
struct CaptureRunnerTests {
    private func makeRunner(
        sequence: CaptureSequence = .standard
    ) async throws -> (CaptureRunner, StubCamera, TestClock) {
        let camera = StubCamera()
        try await camera.start()
        let clock = TestClock()
        return (CaptureRunner(camera: camera, sequence: sequence, clock: clock), camera, clock)
    }

    @Test("a full run captures every frame, in order")
    func fullRun() async throws {
        let (runner, camera, _) = try await makeRunner()
        await runner.run()

        #expect(runner.state == .finished)
        #expect(runner.isComplete)
        #expect(camera.captureCount == 4)
        #expect(runner.frames.map(\.index) == [0, 1, 2, 3])
    }

    @Test("the wait schedule matches the sequence, beat for beat")
    func waitSchedule() async throws {
        let sequence = CaptureSequence(frameCount: 3, countdownSeconds: 2, reviewSeconds: 1.5)
        let (runner, _, clock) = try await makeRunner(sequence: sequence)
        await runner.run()

        let flash = Duration.seconds(CaptureSequence.flashSeconds)
        let review = Duration.seconds(1.5)
        #expect(clock.waits == [
            .seconds(1), .seconds(1), flash, review,
            .seconds(1), .seconds(1), flash, review,
            .seconds(1), .seconds(1), flash,
        ])
    }

    /// The last frame gets no review beat, which is the same subtraction
    /// `CaptureSequence.totalDuration` makes. If the driver and the model ever
    /// disagree, the progress indicator lies; this is what keeps them in step.
    @Test("countdown and review time add up to the advertised duration")
    func matchesTotalDuration() async throws {
        let sequence = CaptureSequence(frameCount: 4, countdownSeconds: 3, reviewSeconds: 1)
        let (runner, _, clock) = try await makeRunner(sequence: sequence)
        await runner.run()

        let flash = Duration.seconds(CaptureSequence.flashSeconds)
        let counted = clock.waits.filter { $0 != flash }.reduce(Duration.zero, +)
        #expect(counted == .seconds(sequence.totalDuration))
    }

    @Test("passes through countdown, flash, and review for each frame")
    func visitsEveryState() async throws {
        let (runner, _, clock) = try await makeRunner()
        var seen: [CaptureRunState] = []
        clock.onWait = { _ in seen.append(runner.state) }
        await runner.run()

        #expect(seen.first == .countingDown(frame: 0, secondsRemaining: 3))
        #expect(seen.contains(.flashing(frame: 0)))
        #expect(seen.contains(.reviewing(frame: 0)))
        // No review after the last frame, so this state never exists.
        #expect(seen.contains(.reviewing(frame: 3)) == false)
    }

    @Test("a camera failure mid-run stops the run and keeps what it had")
    func cameraFailure() async throws {
        let (runner, camera, _) = try await makeRunner()
        camera.failAtCapture = 2

        await runner.run()

        #expect(runner.state == .failed(CaptureError.captureFailed("stub failure").localizedDescription))
        #expect(runner.frames.count == 2)
        #expect(runner.isComplete == false)
    }

    @Test("cancelling mid-run keeps the frames already captured")
    func cancelKeepsFrames() async throws {
        let (runner, _, clock) = try await makeRunner()
        // Four waits in: countdown 3, 2, 1, then the flash for frame 0.
        clock.onWait = { count in
            if count == 5 { runner.cancel() }
        }

        await runner.run()

        #expect(runner.state == .idle)
        #expect(runner.frames.count == 1)
        #expect(runner.isComplete == false)
    }

    @Test("reset clears a finished run")
    func reset() async throws {
        let (runner, _, _) = try await makeRunner()
        await runner.run()
        runner.reset()

        #expect(runner.state == .idle)
        #expect(runner.frames.isEmpty)
    }
}
