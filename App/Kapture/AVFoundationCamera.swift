import AVFoundation
import CoreGraphics
import KaptureKit

/// The only file in the project that imports AVFoundation. Everything else
/// depends on the `CameraSource` protocol, which is what keeps the engine
/// testable without hardware.
final class AVFoundationCamera: NSObject, CameraSource {
    private let session = AVCaptureSession()

    var isRunning: Bool { session.isRunning }

    func start() throws {
        // TODO 1.1: request authorization, discover the device, attach
        // AVCaptureDeviceInput and AVCapturePhotoOutput, then start the session.
        throw CaptureError.noDeviceAvailable
    }

    func stop() {
        session.stopRunning()
    }

    func captureStill() async throws -> CGImage {
        // TODO 1.2: capture through AVCapturePhotoOutput and bridge to CGImage.
        throw CaptureError.sessionNotRunning
    }
}
