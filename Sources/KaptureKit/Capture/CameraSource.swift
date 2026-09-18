import CoreGraphics
import Foundation

/// The camera, behind a protocol so the engine and its tests never link
/// AVFoundation. The real conformance lives in the app target; tests use a stub
/// that returns generated images.
///
/// `start()` is async because authorization is a user-facing prompt and because
/// starting a capture session blocks long enough that it must not run on the
/// main thread.
@MainActor
public protocol CameraSource: AnyObject {
    var isRunning: Bool { get }
    func start() async throws
    func stop()
    func captureStill() async throws -> CGImage
}

public enum CaptureError: Error, Equatable, LocalizedError {
    case permissionDenied
    case noDeviceAvailable
    case sessionNotRunning
    case captureFailed(String)

    /// User-facing text. Camera failures are always shown, never swallowed, and
    /// a denied permission needs a path out rather than a dead end.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Kapture needs camera access. Grant it in System Settings, under Privacy & Security, then Camera."
        case .noDeviceAvailable:
            "No camera was found."
        case .sessionNotRunning:
            "The camera is not running."
        case .captureFailed(let reason):
            reason
        }
    }
}
