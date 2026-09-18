import AVFoundation
import CoreGraphics
import KaptureKit

/// The only file in the project that imports AVFoundation. Everything else
/// depends on the `CameraSource` protocol, which is what keeps the engine
/// testable without hardware.
/// `AVCaptureSession` is not annotated `Sendable`, but Apple's documented
/// pattern is to serialize configuration and start/stop on one dedicated queue
/// while the preview layer attaches from the main thread. This box states that
/// guarantee explicitly, which is honest about what is being asserted;
/// `@preconcurrency import` would only downgrade the diagnostic and assert the
/// same thing silently.
private final class SessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

@MainActor
final class AVFoundationCamera: NSObject, CameraSource {
    private let box = SessionBox()

    /// Exposed so the preview layer can attach to it. Nothing else reads it.
    var session: AVCaptureSession { box.session }

    private let photoOutput = AVCapturePhotoOutput()
    /// Session configuration and start/stop are blocking, so they stay off the
    /// main thread. Apple requires these be serialized.
    private let sessionQueue = DispatchQueue(label: "com.eriklarson.kapture.session")
    private var isConfigured = false
    /// AVFoundation does not retain a photo delegate, so the caller must.
    private var activeDelegate: PhotoCaptureDelegate?

    var isRunning: Bool { box.session.isRunning }

    func start() async throws {
        try await requestAuthorization()
        if !isConfigured {
            try configure()
            isConfigured = true
        }
        let box = self.box
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !box.session.isRunning { box.session.startRunning() }
                continuation.resume()
            }
        }
    }

    func stop() {
        let box = self.box
        sessionQueue.async {
            if box.session.isRunning { box.session.stopRunning() }
        }
    }

    func captureStill() async throws -> CGImage {
        guard isRunning else { throw CaptureError.sessionNotRunning }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                continuation.resume(with: result)
                Task { @MainActor in self?.activeDelegate = nil }
            }
            activeDelegate = delegate
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    private func requestAuthorization() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CaptureError.permissionDenied
            }
        case .denied, .restricted:
            throw CaptureError.permissionDenied
        @unknown default:
            throw CaptureError.permissionDenied
        }
    }

    /// Runs on the main actor. Configuration is fast enough that the blocking
    /// cost is not worth the concurrency complexity of hopping queues here.
    private func configure() throws {
        let session = box.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // Prefer the front camera: a photobooth points at whoever is using it.
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw CaptureError.noDeviceAvailable }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CaptureError.captureFailed("The camera could not be attached to the session.")
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw CaptureError.captureFailed("The photo output could not be attached to the session.")
        }
        session.addOutput(photoOutput)
    }
}

/// Bridges the delegate callback to an async result. Separate from the camera
/// because AVFoundation calls back on its own queue and expects a fresh
/// delegate per capture.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(CaptureError.captureFailed(error.localizedDescription)))
            return
        }
        guard let image = photo.cgImageRepresentation() else {
            completion(.failure(CaptureError.captureFailed("The captured photo contained no image data.")))
            return
        }
        completion(.success(image))
    }
}
