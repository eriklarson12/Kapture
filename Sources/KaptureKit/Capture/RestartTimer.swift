import Foundation
import Observation

/// How a hold ended. `fired` means it ran out, which is the only outcome that
/// starts another run; everything else is somebody deciding otherwise.
public enum RestartOutcome: Equatable, Sendable {
    case fired
    case stopped
}

/// The hold between two strips: a countdown the guest can see and anything can
/// interrupt. Waits through the same injected `CaptureClock` as `CaptureRunner`,
/// and deliberately knows nothing about runs or strips.
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
    /// running is refused. A hold of zero fires at once, so "immediately" needs no special case.
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

    /// Ends the hold at the next beat. `wait` clears the request itself, so
    /// stopping an idle timer cannot silently disarm the next hold.
    public func stop() {
        stopRequested = true
    }

    private var shouldStop: Bool {
        stopRequested || Task.isCancelled
    }
}
