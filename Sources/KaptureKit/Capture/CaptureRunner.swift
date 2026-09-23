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
/// between. Lives in the engine so it can be tested with a stub camera and clock.
@MainActor
@Observable
public final class CaptureRunner {
    public private(set) var state: CaptureRunState = .idle
    public private(set) var frames: [CaptureFrame] = []
    public var sequence: CaptureSequence

    private let camera: any CameraSource
    private let clock: any CaptureClock
    private let cues: any CaptureCueSink
    private var isRunning = false
    private var stopRequested = false

    public init(
        camera: any CameraSource,
        sequence: CaptureSequence = .standard,
        clock: any CaptureClock = SystemCaptureClock(),
        cues: any CaptureCueSink = SilentCueSink()
    ) {
        self.camera = camera
        self.sequence = sequence
        self.clock = clock
        self.cues = cues
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
        cues.play(.finished)
    }

    /// Re-shoots one slot of a strip that already exists. Deliberately does not
    /// touch `frames` or play `.finished` — the re-rendered strip is the review.
    public func captureOne(frame index: Int) async -> CaptureFrame? {
        guard !isRunning else { return nil }
        isRunning = true
        stopRequested = false
        defer { isRunning = false }

        let frame = await shoot(index: index)
        if frame != nil { state = .finished }
        return frame
    }

    /// One shot: countdown, flash, shutter. Shared by `run()` and
    /// `captureOne(frame:)` so a retake can't drift from how a run counts down.
    private func shoot(index: Int) async -> CaptureFrame? {
        for remaining in stride(from: sequence.countdownSeconds, through: 1, by: -1) {
            state = .countingDown(frame: index, secondsRemaining: remaining)
            cues.play(.tick)
            await clock.wait(.seconds(1))
            if shouldStop { state = .idle; return nil }
        }

        // The flash is fill light, so it goes up *before* the shutter and
        // stays up through it. docs/design-system.md.
        state = .flashing(frame: index)
        cues.play(.shutter)
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
