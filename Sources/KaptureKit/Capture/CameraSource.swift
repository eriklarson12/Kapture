import CoreGraphics

/// The camera, behind a protocol so the engine and its tests never link
/// AVFoundation. The real conformance lives in the app target; tests use a stub
/// that returns generated images.
public protocol CameraSource: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
    func captureStill() async throws -> CGImage
}

public enum CaptureError: Error, Equatable {
    case permissionDenied
    case noDeviceAvailable
    case sessionNotRunning
    case captureFailed(String)
}
