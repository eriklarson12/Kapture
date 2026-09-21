import Foundation
import Observation

/// How a hold ended. `fired` means it ran out, which is the only outcome that
/// starts another run; everything else is somebody deciding otherwise.
public enum RestartOutcome: Equatable, Sendable {
    case fired
    case stopped
}

/// The hold between two strips: a countdown the guest can see and anything can
/// interrupt.
///
/// Waits through the same injected `CaptureClock` the driver uses, so a
/// twenty-second hold is a test that takes no time and still asserts twenty
/// beats. It deliberately knows nothing about runs or strips — `CaptureRunner`
/// runs one sequence, and what happens after one is the caller's business.
@MainActor
@Observable
public final class RestartTimer {
    /// The number on screen, and nil whenever no hold is running. The view
    /// branches on exactly this.
    public private(set) var secondsRemaining: Int?
    public var seconds: Int

    private let clock: any CaptureClock
    private var isWaiting = false
    private var stopRequested = false

    public init(seconds: Int = 20, clock: any CaptureClock = SystemCaptureClock()) {
        self.seconds = seconds
        self.clock = clock
    }

    /// Counts down and reports how it ended. A second call while one is already
    /// running is refused, the way `CaptureRunner.run` refuses a second run.
    ///
    /// A hold of zero fires at once and waits for nothing, so turning the
    /// stepper down is a way to say "immediately" rather than a special case.
    public func wait() async -> RestartOutcome {
        guard !isWaiting else { return .stopped }
        isWaiting = true
        stopRequested = false
        defer {
            isWaiting = false
            secondsRemaining = nil
        }

        for remaining in stride(from: seconds, through: 1, by: -1) {
            secondsRemaining = remaining
            await clock.wait(.seconds(1))
            if shouldStop { return .stopped }
        }
        return shouldStop ? .stopped : .fired
    }

    /// Ends the hold at the next beat. Takes effect on the following call too
    /// only if that call has not started: `wait` clears the request itself, so
    /// stopping a timer that is idle cannot silently disarm the next hold.
    public func stop() {
        stopRequested = true
    }

    private var shouldStop: Bool {
        stopRequested || Task.isCancelled
    }
}
