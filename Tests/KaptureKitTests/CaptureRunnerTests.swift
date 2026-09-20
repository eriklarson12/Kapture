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

/// Records the cues a run emits, so the sound schedule is asserted the same
/// way the wait schedule is rather than listened for.
@MainActor
final class TestCueSink: CaptureCueSink {
    private(set) var played: [CaptureCue] = []

    func play(_ cue: CaptureCue) {
        played.append(cue)
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

    private func makeRunner(
        sequence: CaptureSequence = .standard,
        cues: TestCueSink
    ) async throws -> (CaptureRunner, StubCamera, TestClock) {
        let camera = StubCamera()
        try await camera.start()
        let clock = TestClock()
        let runner = CaptureRunner(camera: camera, sequence: sequence, clock: clock, cues: cues)
        return (runner, camera, clock)
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

    // MARK: - Single-frame retake

    @Test("a retake shoots one slot and keeps its index")
    func retakeShootsOneSlot() async throws {
        let (runner, camera, _) = try await makeRunner()
        await runner.run()
        #expect(camera.captureCount == 4)

        let frame = await runner.captureOne(frame: 2)
        #expect(frame?.index == 2)
        #expect(camera.captureCount == 5)
        #expect(runner.state == .finished)
    }

    /// `frames` is the record of a whole run and `isComplete` reads it. A
    /// retake that appended would make a four-shot strip look like a five-shot
    /// one, which the renderer would refuse.
    @Test("a retake leaves the run's own frames alone")
    func retakeDoesNotTouchRunFrames() async throws {
        let (runner, _, _) = try await makeRunner()
        await runner.run()
        let before = runner.frames.map(\.id)

        _ = await runner.captureOne(frame: 0)
        #expect(runner.frames.map(\.id) == before)
        #expect(runner.isComplete)
    }

    @Test("a retake counts down and flashes exactly like a run does")
    func retakeUsesTheSameBeats() async throws {
        let sequence = CaptureSequence(frameCount: 4, countdownSeconds: 2, reviewSeconds: 1.5)
        let (runner, _, clock) = try await makeRunner(sequence: sequence)

        _ = await runner.captureOne(frame: 1)
        // Countdown then flash, and no review beat: the re-rendered strip is
        // the review.
        #expect(clock.waits == [
            .seconds(1), .seconds(1), .seconds(CaptureSequence.flashSeconds),
        ])
    }

    @Test("a failed retake reports itself and returns nothing")
    func retakeFailureSurfaces() async throws {
        let (runner, camera, _) = try await makeRunner()
        camera.failNextCapture = .captureFailed("lens cap")

        let frame = await runner.captureOne(frame: 0)
        #expect(frame == nil)
        #expect(runner.state == .failed(CaptureError.captureFailed("lens cap").localizedDescription))
    }

    // MARK: - Cues

    @Test("a run ticks through every countdown, snaps with every flash, and chimes once")
    func cueSchedule() async throws {
        let sequence = CaptureSequence(frameCount: 3, countdownSeconds: 2, reviewSeconds: 1)
        let cues = TestCueSink()
        let (runner, _, _) = try await makeRunner(sequence: sequence, cues: cues)

        await runner.run()

        #expect(cues.played == [
            .tick, .tick, .shutter,
            .tick, .tick, .shutter,
            .tick, .tick, .shutter,
            .finished,
        ])
    }

    /// The chime says "the strip is up". A retake re-renders a strip that is
    /// already on screen, so there is nothing to turn round and look at.
    @Test("a retake counts down and snaps, and does not chime")
    func retakeDoesNotChime() async throws {
        let sequence = CaptureSequence(frameCount: 4, countdownSeconds: 2, reviewSeconds: 1)
        let cues = TestCueSink()
        let (runner, _, _) = try await makeRunner(sequence: sequence, cues: cues)

        _ = await runner.captureOne(frame: 1)

        #expect(cues.played == [.tick, .tick, .shutter])
    }

    @Test("a cancelled run stops making noise at the beat it stopped on")
    func cancelStopsCues() async throws {
        let cues = TestCueSink()
        let (runner, _, clock) = try await makeRunner(cues: cues)
        // Countdown 3, 2, 1, the flash, then the review beat for frame 0.
        clock.onWait = { count in
            if count == 5 { runner.cancel() }
        }

        await runner.run()

        #expect(cues.played == [.tick, .tick, .tick, .shutter])
    }

    /// A chime after a failure would be a lie. The error panel is the report.
    @Test("a camera failure mid-run never chimes")
    func failureDoesNotChime() async throws {
        let cues = TestCueSink()
        let (runner, camera, _) = try await makeRunner(cues: cues)
        camera.failAtCapture = 2

        await runner.run()

        #expect(cues.played.contains(.finished) == false)
        #expect(cues.played.filter { $0 == .shutter }.count == 3)
    }
}
