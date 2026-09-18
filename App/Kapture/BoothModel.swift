import CoreGraphics
import Foundation
import KaptureKit
import Observation

/// One finished strip, held as both the stored recipe and the image rendered
/// from it. The recipe is the truth; the image is a view of it at one scale.
struct RenderedStrip: Identifiable {
    var recipe: StripRecipe
    var image: CGImage
    var id: UUID { recipe.id }
}

enum CameraStatus: Equatable {
    case starting
    case live
    case failed(String)
}

/// App state: the camera, the run in progress, and the strip that came out of
/// it. All the policy lives here so the views stay declarative.
@MainActor
@Observable
final class BoothModel {
    let camera = AVFoundationCamera()
    let store: StripStore
    let runner: CaptureRunner

    private(set) var cameraStatus: CameraStatus = .starting
    private(set) var strip: RenderedStrip?
    private(set) var isBuilding = false
    var isExporting = false
    var errorMessage: String?

    /// The template owns the shot count. Letting the sequence carry a second,
    /// independent count is how you get a three-shot run rendered into a
    /// four-frame strip, which the renderer rightly refuses.
    var templateID = BuiltInTemplates.classicStrip.id {
        didSet { sequence.frameCount = template.frameCount }
    }

    var sequence = CaptureSequence.standard {
        didSet { runner.sequence = sequence }
    }

    /// Templates are addressed by id so the picker selects one rather than
    /// editing the selected one's identity.
    var template: StripTemplate {
        BuiltInTemplates.template(id: templateID) ?? BuiltInTemplates.classicStrip
    }

    var isRunning: Bool {
        switch runner.state {
        case .idle, .finished, .failed: false
        default: true
        }
    }

    var canCapture: Bool {
        cameraStatus == .live && !isRunning && !isBuilding && !isExporting
    }

    init(root: URL = .kaptureSupportDirectory) {
        let store = StripStore(root: root)
        self.store = store
        self.runner = CaptureRunner(camera: camera, sequence: .standard)
        self.sequence.frameCount = template.frameCount
    }

    func startCamera() async {
        do {
            try await camera.start()
            cameraStatus = .live
        } catch {
            cameraStatus = .failed(error.localizedDescription)
        }
    }

    func stopCamera() {
        camera.stop()
    }

    /// Runs the sequence, stores the frames, and renders the strip.
    func capture() async {
        strip = nil
        errorMessage = nil
        runner.reset()

        await runner.run()

        if case .failed(let message) = runner.state {
            errorMessage = message
            return
        }
        guard runner.isComplete else { return }
        await buildStrip()
    }

    func retake() {
        strip = nil
        runner.reset()
    }

    private func buildStrip() async {
        isBuilding = true
        defer { isBuilding = false }
        do {
            let recipe = try store.save(frames: runner.frames, templateID: templateID)
            let image = try await render(recipe, scale: Self.previewScale)
            strip = RenderedStrip(recipe: recipe, image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Compositing a 600x1800 canvas is not main-thread work, so the render
    /// happens off the actor and only the finished image comes back.
    private func render(_ recipe: StripRecipe, scale: CGFloat) async throws -> CGImage {
        let renderer = RecipeRenderer(store: store)
        return try await Task.detached(priority: .userInitiated) {
            try renderer.render(recipe, scale: scale)
        }.value
    }

    /// Enough resolution for a Retina display without paying for a print.
    private static let previewScale: CGFloat = 3
}

extension URL {
    /// Under the sandbox this resolves inside the app's own container.
    static var kaptureSupportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Kapture", directoryHint: .isDirectory)
    }
}
