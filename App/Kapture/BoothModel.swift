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
    #if DEBUG
    let camera: any CameraSource = DemoMode.root.map {
        DemoCamera(directory: $0.appending(path: "Photos", directoryHint: .isDirectory))
    } ?? AVFoundationCamera()
    #else
    let camera = AVFoundationCamera()
    #endif
    /// Built before the runner, because the runner is handed it.
    let sounds = BoothSounds()
    let store: StripStore
    let templateStore: TemplateStore
    let runner: CaptureRunner
    /// The hold between two strips in a queue. Lives here because the key handling,
    /// the hint line and the inspector all read it.
    let restart = RestartTimer()

    /// Held rather than read on demand, because every preview render asks for a
    /// template and reading files to answer would be absurd.
    private(set) var userTemplates: [StripTemplate] = []

    private(set) var cameraStatus: CameraStatus = .starting
    private(set) var strip: RenderedStrip?
    private(set) var isBuilding = false
    /// So the viewport shows the camera rather than the strip while retaking.
    private(set) var retakingFrame: Int?
    var isExporting = false
    /// A copy leaves no panel and no file, so the menu item says it happened
    /// for a moment. Nothing else would.
    var didCopy = false
    var errorMessage: String?
    /// Separate from `errorMessage`, which is titled as a failure and would be
    /// the wrong frame for "Added a template".
    var notice: String?
    /// The template the editor is open on, if it is open. Nil dismisses it.
    var editingTemplate: TemplateEdit?
    /// Lives here because the View menu, layout and key handling all read it.
    /// Leaving kiosk stops the queue too, so it can't restart behind an open inspector.
    var isKiosk = false {
        didSet { if !isKiosk { stopQueue() } }
    }

    /// Off by default and kiosk-only: anywhere else this is a timer that throws
    /// away the strip somebody is working on.
    var autoRestart = false

    /// So a party is captioned once rather than once per run. Each strip still
    /// stores its own text; this is what a new one starts from.
    var standingCaption = ""

    /// A picture is held as well as named because an asset id belongs to one
    /// strip's package (ADR-012); the image is what gets copied into each new one.
    var standingBackdrop: StripBackground?
    @ObservationIgnored var standingBackdropImage: CGImage?

    /// On for strips shot from now; a strip already on disk has no such key
    /// and stays centred (ADR-025). Standing, like the backdrop.
    var standingFaceFraming = true

    /// Never on at launch: serving photographs to a network nobody asked to join
    /// isn't a default anyone would choose. Written by `StripSharing.swift`.
    var isSharing = false
    var shareURL: URL?
    var shareQR: CGImage?
    /// A server that will not start is text on screen, never a switch that
    /// silently does nothing.
    var shareError: String?

    @ObservationIgnored var server: StripServer?
    @ObservationIgnored var sharePort: UInt16?
    @ObservationIgnored var shareToken: ShareToken?
    @ObservationIgnored var sharedRecipe: UUID?

    /// Guards against an out-of-order render: dragging a colour emits a stream of
    /// edits, and a slow one landing after a fast one would show a stale strip.
    @ObservationIgnored private var renderGeneration = 0

    /// The running queue, held so anything can stop it.
    @ObservationIgnored private var queue: Task<Void, Never>?

    /// The template owns the shot count; a sequence with its own independent
    /// count is how a three-shot run ends up rendered into a four-frame strip.
    var templateID = BuiltInTemplates.classicStrip.id {
        didSet { sequence.frameCount = template.frameCount }
    }

    var sequence = CaptureSequence.standard {
        didSet { runner.sequence = sequence }
    }

    /// The one lookup every render path takes; a strip shot with an imported
    /// template renders only because this is what reaches `RecipeRenderer` (ADR-014).
    var templates: [String: StripTemplate] {
        TemplateStore.catalogue(with: userTemplates)
    }

    /// Built-ins first, in their own order, then the user's by name. The
    /// shipped three stay where they have always been in the picker.
    var allTemplates: [StripTemplate] {
        BuiltInTemplates.all + userTemplates
    }

    /// The one renderer the app builds; every export path used to construct its own
    /// with the built-ins only, a bug an imported template found on the next launch.
    var renderer: RecipeRenderer {
        RecipeRenderer(store: store, templates: templates, masks: masks, faces: faces)
    }

    /// One set of person masks for the whole app: every export path goes through
    /// `renderer`, so all outputs share it and a frame is segmented once.
    @ObservationIgnored private let masks = PersonMaskStore()
    /// Faces found once per frame, for the same reason.
    @ObservationIgnored private let faces = FaceStore()

    /// Templates are addressed by id so the picker selects one rather than
    /// editing the selected one's identity.
    var template: StripTemplate {
        templates[templateID] ?? BuiltInTemplates.classicStrip
    }

    /// The base template with this strip's overrides applied, so an untouched
    /// inspector control shows what the template gives rather than blank.
    var shownTemplate: StripTemplate {
        let base = templates[strip?.recipe.templateID ?? templateID]
            ?? BuiltInTemplates.classicStrip
        return base.applying(strip?.recipe.style)
    }

    /// A four-frame strip cannot be re-rendered into a three-frame template, so
    /// while one is shown the picker offers only templates that can hold it.
    var availableTemplates: [StripTemplate] {
        guard let strip else { return allTemplates }
        return allTemplates.filter { $0.frameCount == strip.recipe.frameIDs.count }
    }

    var isRunning: Bool {
        switch runner.state {
        case .idle, .finished, .failed: false
        default: true
        }
    }

    /// True while a finished strip is being held before the next run starts.
    var isHolding: Bool {
        restart.secondsRemaining != nil
    }

    var canCapture: Bool {
        cameraStatus == .live && !isRunning && !isBuilding && !isExporting
            && retakingFrame == nil
    }

    init(root: URL = .kaptureSupportDirectory) {
        self.store = StripStore(root: root)
        self.templateStore = TemplateStore(root: root)
        self.runner = CaptureRunner(camera: camera, sequence: .standard, cues: sounds)
        // A template that cannot be read leaves the built-ins standing. The
        // app must start.
        self.userTemplates = (try? templateStore.load()) ?? []
        self.sequence.frameCount = template.frameCount
    }

    /// Shows a line about something that worked, and takes it away again. A
    /// report with no dismissal would sit over the viewport until the next one.
    func report(_ message: String) {
        notice = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if notice == message { notice = nil }
        }
    }

    /// The catalogue is derived from these, so this is the only thing that
    /// has to be refreshed after a save, import or removal.
    func reloadTemplates() {
        do {
            userTemplates = try templateStore.load()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Called during a hold, this cancels that hold and shoots now, so one key
    /// covers both cases. Without auto-restart it runs exactly once.
    func startQueue() {
        queue?.cancel()
        restart.stop()
        queue = Task { [weak self] in await self?.runQueue() }
    }

    func stopQueue() {
        queue?.cancel()
        queue = nil
        restart.stop()
        runner.cancel()
    }

    private func runQueue() async {
        repeat {
            await capture()
            // A failure ends the queue: counting down into a failed camera would
            // just redraw the same error forever, with no gap to fix it.
            guard isKiosk, autoRestart, strip != nil, errorMessage == nil,
                  !Task.isCancelled else { return }
        } while await restart.wait() == .fired
    }

    /// One field, two effects: it captions the strip on screen and every strip
    /// shot after it.
    func setCaption(_ text: String) {
        standingCaption = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard strip != nil else { return }
        Task { await restyle { $0.caption = trimmed.isEmpty ? nil : text } }
    }

    /// One field, two effects, like the caption: it changes the strip on screen
    /// and every strip shot after it.
    func setBackdrop(_ backdrop: StripBackground?) async {
        standingBackdrop = backdrop
        // Dropped whenever the backdrop stops being a picture, so the held
        // image and the recorded one cannot describe different things.
        if case .image = backdrop {} else { standingBackdropImage = nil }
        guard strip != nil else { return }
        await restyle { $0.backdrop = backdrop }
    }

    /// Standing, like the backdrop: the strip on screen and every one after it.
    func setFaceFraming(_ on: Bool) async {
        standingFaceFraming = on
        guard strip != nil else { return }
        await restyle { $0.faceFraming = on }
    }

    /// Fitted to the photo band, not the canvas — unlike `setBackgroundImage`,
    /// a backdrop composites inside one photograph, not across the paper.
    func setBackdropImage(_ image: CGImage) async {
        guard let current = strip else { return }
        do {
            let fitted = StripRenderer.downscaled(image, covering: photoPixelSize)
            let assetID = try store.saveAsset(fitted, in: current.recipe.id)
            standingBackdrop = .image(id: assetID)
            standingBackdropImage = fitted
            await restyle { $0.backdrop = .image(id: assetID) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The pixels one photograph occupies on a 300 dpi print. The same size
    /// `RecipeRenderer` shrinks a frame to for a PDF.
    private var photoPixelSize: CGSize {
        let template = shownTemplate
        let scale = template.scale(forDPI: 300)
        return CGSize(width: template.photoWidth * scale, height: template.photoHeight * scale)
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

    /// The one path from an edited recipe to a visible, saved strip — the single
    /// place that knows how to re-render and persist.
    func restyle(_ mutate: (inout StripRecipe) -> Void) async {
        guard let current = strip else { return }
        var recipe = current.recipe
        mutate(&recipe)
        guard recipe != current.recipe else { return }
        await present(recipe, persisting: true)
    }

    /// Rewritten by `replaceFrame` rather than `present`, because the new
    /// frame has to reach disk before a recipe can name it.
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

    /// Copied rather than referenced (ADR-012), so moving or deleting the
    /// original cannot break a strip that already exists.
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

    /// A template edit changes what a recipe *means*, not what it says, so
    /// `restyle` sees no difference. Nothing is persisted: disk is already correct.
    func refreshStrip() async {
        guard let recipe = strip?.recipe else { return }
        await present(recipe, persisting: false)
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
            // The previously shown strip stays up; blanking on a failed edit
            // would lose work that is still on disk.
            errorMessage = error.localizedDescription
        }
    }

    private func buildStrip() async {
        isBuilding = true
        defer { isBuilding = false }
        do {
            let trimmed = standingCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            var recipe = try store.save(
                frames: runner.frames,
                templateID: templateID,
                caption: trimmed.isEmpty ? nil : standingCaption,
                // Attached afterwards, once there is a package to copy it into —
                // writing the standing id here would name an asset from a different strip.
                backdrop: standingBackdropImage == nil ? standingBackdrop : nil,
                faceFraming: standingFaceFraming
            )
            recipe = try carryBackdropPicture(onto: recipe)
            let image = try await render(recipe, scale: Self.previewScale)
            strip = RenderedStrip(recipe: recipe, image: image)
            // Withdrawn here, not when the run started, so a guest scanning at
            // the end of a hold keeps the whole next run to finish.
            share(recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The standing backdrop's id names an asset inside the strip it was chosen
    /// on, so every strip needs its own copy to stay a self-contained folder (ADR-011, ADR-012).
    private func carryBackdropPicture(onto recipe: StripRecipe) throws -> StripRecipe {
        guard case .image = standingBackdrop, let picture = standingBackdropImage else {
            return recipe
        }
        var copied = recipe
        copied.backdrop = .image(id: try store.saveAsset(picture, in: recipe.id))
        try store.update(copied)
        return copied
    }

    /// Compositing a 600x1800 canvas is not main-thread work, so the render
    /// happens off the actor and only the finished image comes back.
    private func render(_ recipe: StripRecipe, scale: CGFloat) async throws -> CGImage {
        let renderer = self.renderer
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
