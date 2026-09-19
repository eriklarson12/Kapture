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
    /// Which shot is being re-taken, so the viewport shows the camera rather
    /// than the strip the user is standing in front of.
    private(set) var retakingFrame: Int?
    var isExporting = false
    /// A copy leaves no panel and no file, so the menu item says it happened
    /// for a moment. Nothing else would.
    var didCopy = false
    var errorMessage: String?

    /// Guards against an out-of-order render. Dragging a colour emits a stream
    /// of edits, and a slow render landing after a fast one would show a strip
    /// that no longer matches the recipe.
    @ObservationIgnored private var renderGeneration = 0

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

    /// The template as the shown strip actually renders it: the base template
    /// with this strip's overrides applied. The inspector displays these values,
    /// so an untouched control shows what the template gives rather than blank.
    var shownTemplate: StripTemplate {
        let base = BuiltInTemplates.template(id: strip?.recipe.templateID ?? templateID)
            ?? BuiltInTemplates.classicStrip
        return base.applying(strip?.recipe.style)
    }

    /// A four-frame strip cannot be re-rendered into a three-frame template, so
    /// while one is shown the picker offers only templates that can hold it.
    var availableTemplates: [StripTemplate] {
        guard let strip else { return BuiltInTemplates.all }
        return BuiltInTemplates.all.filter { $0.frameCount == strip.recipe.frameIDs.count }
    }

    var isRunning: Bool {
        switch runner.state {
        case .idle, .finished, .failed: false
        default: true
        }
    }

    var canCapture: Bool {
        cameraStatus == .live && !isRunning && !isBuilding && !isExporting
            && retakingFrame == nil
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
        retakingFrame = nil
        runner.reset()
    }

    /// Picks the template for the next run, and re-renders the shown strip into
    /// it when there is one.
    func selectTemplate(_ id: String) async {
        templateID = id
        guard strip != nil else { return }
        await restyle { $0.templateID = id }
    }

    /// The one path from an edited recipe to a visible, saved strip. Items 2.1,
    /// 2.2, 2.3, 2.4 and 2.6 all route through here, so there is a single place
    /// that knows how to re-render and persist.
    func restyle(_ mutate: (inout StripRecipe) -> Void) async {
        guard let current = strip else { return }
        var recipe = current.recipe
        mutate(&recipe)
        guard recipe != current.recipe else { return }
        await present(recipe, persisting: true)
    }

    /// Re-shoots one photo of the shown strip, leaving the other three alone.
    ///
    /// The package is rewritten by `replaceFrame` rather than by `present`,
    /// because the new frame has to reach disk before a recipe can name it.
    func retakeFrame(_ index: Int) async {
        guard let current = strip, retakingFrame == nil else { return }
        errorMessage = nil
        retakingFrame = index
        defer { retakingFrame = nil }

        guard let frame = await runner.captureOne(frame: index) else {
            if case .failed(let message) = runner.state { errorMessage = message }
            return
        }
        do {
            let recipe = try store.replaceFrame(frame.image, at: index, in: current.recipe)
            await present(recipe, persisting: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Copies a picture into the strip's own package and points the background
    /// at it (ADR-012). Copied rather than referenced, so moving or deleting
    /// the original cannot break a strip that already exists.
    func setBackgroundImage(_ image: CGImage) async {
        guard let current = strip else { return }
        do {
            let fitted = StripRenderer.downscaled(
                image, covering: shownTemplate.pixelSize(atDPI: 300)
            )
            let assetID = try store.saveAsset(fitted, in: current.recipe.id)
            await restyle { recipe in
                var style = recipe.style ?? StripStyle()
                style.background = .image(id: assetID)
                recipe.style = style
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renders, optionally persists, and shows. The generation guard lives here
    /// so no edit path can skip it.
    private func present(_ recipe: StripRecipe, persisting: Bool) async {
        renderGeneration &+= 1
        let generation = renderGeneration
        do {
            let image = try await render(recipe, scale: Self.previewScale)
            // A newer edit has already started; its render is the one to show.
            guard generation == renderGeneration else { return }
            if persisting { try store.update(recipe) }
            strip = RenderedStrip(recipe: recipe, image: image)
        } catch {
            // The previously shown strip stays up. Blanking the viewport on a
            // failed edit would lose work that is still on disk.
            errorMessage = error.localizedDescription
        }
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
