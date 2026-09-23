import Foundation

/// A moment in a run worth marking out loud. The driver names the moment;
/// what it sounds like is decided elsewhere.
public enum CaptureCue: String, CaseIterable, Equatable, Sendable {
    /// One second of the countdown has gone by.
    case tick
    /// The shutter, fired with the flash rather than after it.
    case shutter
    /// A whole run finished and the strip is about to appear.
    case finished
}

/// Where a cue goes, injected the way `CaptureClock` is and for the same
/// reason: a schedule a test can assert rather than sit through.
@MainActor
public protocol CaptureCueSink {
    func play(_ cue: CaptureCue)
}

/// The default. A driver nobody handed a sink is silent rather than broken,
/// which is what every headless caller and every existing test wants.
public struct SilentCueSink: CaptureCueSink {
    public init() {}
    public func play(_ cue: CaptureCue) {}
}
