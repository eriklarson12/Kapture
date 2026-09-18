import Foundation

/// The driver's only source of elapsed time, behind a protocol so a test can
/// run a four-shot sequence instantly and still assert the timing.
///
/// A real clock makes the capture tests take `CaptureSequence.totalDuration`
/// seconds each, which is slow enough that nobody runs them. A stub that also
/// *records* what it was asked to wait for turns the timing plan into something
/// assertable rather than merely fast.
@MainActor
public protocol CaptureClock {
    func wait(_ duration: Duration) async
}

public struct SystemCaptureClock: CaptureClock {
    public init() {}

    public func wait(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
