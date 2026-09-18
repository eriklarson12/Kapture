import CoreGraphics
import Testing
@testable import KaptureKit

/// Stands in for a camera. Its existence is the point: if `CameraSource` ever
/// stops being implementable without AVFoundation, this file stops compiling
/// and the engine has quietly grown a hardware dependency.
@MainActor
final class StubCamera: CameraSource {
    private(set) var isRunning = false
    private(set) var captureCount = 0
    var failNextCapture: CaptureError?

    func start() async throws {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func captureStill() async throws -> CGImage {
        guard isRunning else { throw CaptureError.sessionNotRunning }
        if let failNextCapture {
            self.failNextCapture = nil
            throw failNextCapture
        }
        captureCount += 1
        return TestImage.solid(width: 640, height: 480)
    }
}

@Suite("CameraSource")
@MainActor
struct CameraSourceTests {
    @Test("refuses to capture before it is started")
    func captureBeforeStart() async {
        let camera = StubCamera()
        await #expect(throws: CaptureError.sessionNotRunning) {
            try await camera.captureStill()
        }
    }

    @Test("captures once started, and stops")
    func lifecycle() async throws {
        let camera = StubCamera()
        try await camera.start()
        #expect(camera.isRunning)

        let image = try await camera.captureStill()
        #expect(image.width == 640)
        #expect(camera.captureCount == 1)

        camera.stop()
        #expect(camera.isRunning == false)
    }

    @Test("a full sequence's worth of frames feeds the renderer")
    func feedsRenderer() async throws {
        let camera = StubCamera()
        try await camera.start()

        let template = BuiltInTemplates.classicStrip
        var frames: [CGImage] = []
        for _ in 0..<template.frameCount {
            frames.append(try await camera.captureStill())
        }

        let strip = try StripRenderer().render(frames: frames, template: template)
        #expect(strip.width == Int(template.canvasSize.width))
        #expect(camera.captureCount == template.frameCount)
    }

    @Test("surfaces a permission failure with usable text")
    func permissionMessage() {
        let message = CaptureError.permissionDenied.errorDescription ?? ""
        #expect(message.contains("System Settings"))
    }
}
