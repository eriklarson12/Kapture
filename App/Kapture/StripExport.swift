import AppKit
import KaptureKit
import UniformTypeIdentifiers

/// Export policy: what the file is called and at what resolution it lands.
enum StripExport {
    /// Print resolution. The classic strip at 300 dpi is 600x1800 pixels,
    /// which is a true 2x6 inches.
    static let dpi: CGFloat = 300

    static func filename(for recipe: StripRecipe) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Kapture-\(formatter.string(from: recipe.createdAt)).png"
    }
}

extension BoothModel {
    /// Renders the strip again at print resolution and writes it where the user
    /// chooses. The preview render is thrown away rather than upscaled, which
    /// is the whole point of storing a recipe instead of a raster.
    func exportStrip() async {
        guard let strip else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = StripExport.filename(for: strip.recipe)
        panel.message = "Export this strip as a \(Int(StripExport.dpi)) dpi PNG."

        guard await panel.begin() == .OK, let url = panel.url else { return }

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
}
