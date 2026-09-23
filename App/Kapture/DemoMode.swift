#if DEBUG
import CoreGraphics
import ImageIO
import KaptureKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Debug builds only. Stock photos stand in for the camera, and the app opens on
/// one scene, so the landing page screenshots can be retaken without a person in
/// front of the Mac.
///
/// `KAPTURE_DEMO` names a directory holding `Photos/*.jpg`. It is also the store
/// root, so a demo run never writes into the real library.
/// `KAPTURE_DEMO_SCENE` is `capture`, `editor` or `templates`.
enum DemoMode {
    static let root: URL? = ProcessInfo.processInfo.environment["KAPTURE_DEMO"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }

    private static var scene: String? {
        ProcessInfo.processInfo.environment["KAPTURE_DEMO_SCENE"]
    }

    @MainActor
    static func play(_ model: BoothModel) async {
        guard root != nil, let scene else { return }
        while model.cameraStatus == .starting {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard model.cameraStatus == .live else { return }

        switch scene {
        case "capture":
            model.startQueue()
        case "editor":
            model.sequence.countdownSeconds = 1
            model.sequence.reviewSeconds = 0.2
            await model.capture()
            // One edit, not `setCaption` and then a restyle: the caption's own
            // render would land last and drop the style.
            model.standingCaption = "Winter market"
            await model.restyle { recipe in
                recipe.caption = model.standingCaption
                var style = recipe.style ?? StripStyle()
                style.background = .solid(RGBA(red: 0.96, green: 0.92, blue: 0.84))
                style.foreground = RGBA(red: 0.17, green: 0.27, blue: 0.21)
                recipe.style = style
            }
            await exportStrip(model)
        case "templates":
            model.templateID = BuiltInTemplates.gridQuad.id
            model.editTemplate()
        default:
            break
        }
    }

    /// Writes the shown strip at print resolution, as Save Strip would, without
    /// the save panel.
    @MainActor
    private static func exportStrip(_ model: BoothModel) async {
        guard let root, let recipe = model.strip?.recipe else { return }
        let renderer = model.renderer
        guard let scale = try? renderer.template(for: recipe).scale(forDPI: StripExport.dpi),
              let image = try? renderer.render(recipe, scale: scale),
              let destination = CGImageDestinationCreateWithURL(
                  root.appending(path: "strip.png") as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// Hands out the stock photos in name order, looping.
@MainActor
@Observable
final class DemoCamera: CameraSource {
    private let photos: [CGImage]
    private var next = 0
    private(set) var isRunning = false

    /// What the preview shows: the photo the next capture returns.
    var current: CGImage? { photos.isEmpty ? nil : photos[next % photos.count] }

    init(directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        photos = files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                CGImageSourceCreateWithURL(url as CFURL, nil)
                    .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            }
    }

    func start() async throws {
        guard !photos.isEmpty else { throw CaptureError.noDeviceAvailable }
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func captureStill() async throws -> CGImage {
        guard isRunning, let image = current else { throw CaptureError.sessionNotRunning }
        next += 1
        return image
    }
}

/// Mirrored, like the real preview.
struct DemoPreview: View {
    let camera: DemoCamera

    var body: some View {
        if let image = camera.current {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .scaleEffect(x: -1, y: 1)
        }
    }
}
#endif
