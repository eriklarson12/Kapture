import AppKit
import KaptureKit
import UniformTypeIdentifiers

/// Export policy: what each file is called, how big it is, and how fast it
/// plays. Three formats now share one timestamp, so a strip's PNG, GIF and
/// movie sort together in a folder.
enum StripExport {
    /// Print resolution. The classic strip at 300 dpi is 600x1800 pixels,
    /// which is a true 2x6 inches.
    static let dpi: CGFloat = 300

    /// Small enough to send. A GIF is 256 colours whatever size it is, so
    /// spending pixels on it buys file size and not much else.
    static let gifHeight: CGFloat = 400
    static let gifDelay: Double = 0.6

    /// The frames arrive 1080 tall, so this is the largest size that never
    /// upscales.
    static let movieHeight: CGFloat = 1080
    static let movieSecondsPerFrame: Double = 0.8

    static func filename(for recipe: StripRecipe, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Kapture-\(formatter.string(from: recipe.createdAt)).\(ext)"
    }
}

extension BoothModel {
    /// Renders the strip again at print resolution and writes it where the user
    /// chooses. The preview render is thrown away rather than upscaled, which
    /// is the whole point of storing a recipe instead of a raster.
    func exportStrip() async {
        guard let strip else { return }
        guard let url = await save(
            strip.recipe,
            type: .png,
            ext: "png",
            message: "Export this strip as a \(Int(StripExport.dpi)) dpi PNG."
        ) else { return }

        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = RecipeRenderer(store: store)
            let scale = try renderer.template(for: strip.recipe).scale(forDPI: StripExport.dpi)
            let recipe = strip.recipe
            let data = try await Task.detached(priority: .userInitiated) {
                let image = try renderer.render(recipe, scale: scale)
                return try ImageCodec.encodePNG(image, dpi: StripExport.dpi)
            }.value
            try data.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The shots as a looping GIF. Not the strip: the paper does not animate,
    /// and a face is what people send each other.
    func exportGIF() async {
        guard let strip else { return }
        guard let url = await save(
            strip.recipe,
            type: .gif,
            ext: "gif",
            message: "Export the shots as a looping GIF."
        ) else { return }

        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = RecipeRenderer(store: store)
            let recipe = strip.recipe
            let data = try await Task.detached(priority: .userInitiated) {
                let frames = try renderer.renderFrames(recipe, height: StripExport.gifHeight)
                return try ImageCodec.encodeGIF(frames, delaySeconds: StripExport.gifDelay)
            }.value
            try data.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The same shots as an MP4, which plays inline on a phone and keeps the
    /// colours a GIF has to throw away.
    func exportMovie() async {
        guard let strip else { return }
        guard let url = await save(
            strip.recipe,
            type: .mpeg4Movie,
            ext: "mp4",
            message: "Export the shots as a movie."
        ) else { return }

        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = RecipeRenderer(store: store)
            let recipe = strip.recipe
            let frames = try await Task.detached(priority: .userInitiated) {
                try renderer.renderFrames(recipe, height: StripExport.movieHeight)
            }.value
            try await MovieRenderer.writeMP4(
                frames: frames,
                secondsPerFrame: StripExport.movieSecondsPerFrame,
                to: url
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The save panel the three exports share, so they cannot drift on naming
    /// or on what a cancel does.
    private func save(
        _ recipe: StripRecipe, type: UTType, ext: String, message: String
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = StripExport.filename(for: recipe, ext: ext)
        panel.message = message
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}
