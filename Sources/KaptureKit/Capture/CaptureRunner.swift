import Foundation
import Observation

/// Where a run is, moment to moment. The app renders directly from this: the
/// countdown overlay, the flash, and the review beat are each one case.
public enum CaptureRunState: Equatable, Sendable {
    case idle
    case countingDown(frame: Int, secondsRemaining: Int)
    case flashing(frame: Int)
    case reviewing(frame: Int)
    case finished
    case failed(String)
}

/// Drives one photobooth run: N shots, a countdown before each, a review beat
/// between. Lives in the engine rather than the view so it can be tested
/// against a stub camera and a stub clock, with no hardware and no waiting.
@MainActor
@Observable
public final class CaptureRunner {
    public private(set) var state: CaptureRunState = .idle
    public private(set) var frames: [CaptureFrame] = []
    public var sequence: CaptureSequence

    private let camera: any CameraSource
    private let clock: any CaptureClock
    private var isRunning = false
    private var stopRequested = false

    public init(
        camera: any CameraSource,
        sequence: CaptureSequence = .standard,
        clock: any CaptureClock = SystemCaptureClock()
    ) {
        self.camera = camera
        self.sequence = sequence
        self.clock = clock
    }

    /// True once every frame is in hand, which is when the strip can be built.
    public var isComplete: Bool {
        state == .finished && frames.count == sequence.frameCount
    }

    public func run() async {
        guard !isRunning else { return }
        isRunning = true
        stopRequested = false
        frames = []
        defer { isRunning = false }

        for index in 0..<sequence.frameCount {
            guard let frame = await shoot(index: index) else { return }
            frames.append(frame)
            if shouldStop { state = .idle; return }

            // No review beat after the last shot; the strip is what comes next.
            // `CaptureSequence.totalDuration` subtracts one for the same reason.
            if index < sequence.frameCount - 1 {
                state = .reviewing(frame: index)
                await clock.wait(.seconds(sequence.reviewSeconds))
                if shouldStop { state = .idle; return }
            }
        }

        state = .finished
    }

    /// Re-shoots one slot of a strip that already exists.
    ///
    /// Deliberately does not touch `frames`: that array is the record of a
    /// whole run, and `isComplete` has to keep meaning "a run finished" rather
    /// than "the last thing that happened produced an image". There is no
    /// review beat either — the re-rendered strip is the review.
    public func captureOne(frame index: Int) async -> CaptureFrame? {
        guard !isRunning else { return nil }
        isRunning = true
        stopRequested = false
        defer { isRunning = false }

        let frame = await shoot(index: index)
        if frame != nil { state = .finished }
        return frame
    }

    /// One shot: countdown, flash, shutter. Returns nil when the run was
    /// stopped or the camera failed, having already set the state that says
    /// which. Shared by `run()` and `captureOne(frame:)` so a retake cannot
    /// drift away from a run in how it counts down or when it fires.
    private func shoot(index: Int) async -> CaptureFrame? {
        for remaining in stride(from: sequence.countdownSeconds, through: 1, by: -1) {
            state = .countingDown(frame: index, secondsRemaining: remaining)
            await clock.wait(.seconds(1))
            if shouldStop { state = .idle; return nil }
        }

        // The flash is fill light, so it goes up *before* the shutter and
        // stays up through it. docs/design-system.md.
        state = .flashing(frame: index)
        await clock.wait(.seconds(CaptureSequence.flashSeconds))

        do {
            return CaptureFrame(index: index, image: try await camera.captureStill())
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Stops at the next beat. Frames already captured are kept, so a cancelled
    /// run can be inspected rather than silently discarded.
    public func cancel() {
        stopRequested = true
    }

    public func reset() {
        stopRequested = false
        frames = []
        state = .idle
    }

    private var shouldStop: Bool {
        stopRequested || Task.isCancelled
    }
}
