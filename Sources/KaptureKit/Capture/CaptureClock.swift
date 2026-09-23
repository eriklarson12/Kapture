import Foundation

/// The driver's only source of elapsed time, behind a protocol so a test stub
/// can run a sequence instantly while still recording what it was asked to wait for.
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
