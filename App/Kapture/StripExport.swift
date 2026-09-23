import AppKit
import KaptureKit
import UniformTypeIdentifiers

/// Every format shares one timestamp, so a strip's PNG, GIF, movie and PDF
/// sort together in a folder.
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

    /// Higher buys nothing a printer can use: a real four-shot strip is 12.6 MB
    /// with the stored frames embedded and 2.1 MB at 300 dpi.
    static let pdfPhotoDPI: CGFloat = 300

    /// `scalingFactor` is the one value that must stay at 1. Anything else and
    /// the strip stops being two inches wide, and only a ruler will show it.
    static func printInfo(pageSize: CGSize) -> NSPrintInfo {
        let inherited = NSPrintInfo.shared.dictionary() as? [NSPrintInfo.AttributeKey: Any]
        let info = inherited.map(NSPrintInfo.init(dictionary:)) ?? NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.scalingFactor = 1
        return info
    }

    static func filename(for recipe: StripRecipe, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Kapture-\(formatter.string(from: recipe.createdAt)).\(ext)"
    }
}

extension BoothModel {
    /// The preview render is thrown away rather than upscaled, which is the
    /// whole point of storing a recipe instead of a raster.
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
            let renderer = self.renderer
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
            let renderer = self.renderer
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
            let renderer = self.renderer
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

    /// A PNG asks to be printed at 2x6 inches through metadata some print paths
    /// ignore; a PDF's page box measures two by six and can't be read any other way.
    func exportPDF() async {
        guard let strip else { return }
        guard let url = await save(
            strip.recipe,
            type: .pdf,
            ext: "pdf",
            message: "Export this strip as a PDF that prints at a true 2x6 inches."
        ) else { return }

        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = self.renderer
            let recipe = strip.recipe
            let data = try await Task.detached(priority: .userInitiated) {
                try renderer.renderPDF(recipe, photoDPI: StripExport.pdfPhotoDPI)
            }.value
            try data.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A consumer takes the first declared type it understands, so PNG (a
    /// photograph) goes first; PDF is there for anything that asks to scale.
    func copyStrip() async {
        guard let strip else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = self.renderer
            let recipe = strip.recipe
            let scale = try renderer.template(for: recipe).scale(forDPI: StripExport.dpi)
            let flavours = try await Task.detached(priority: .userInitiated) {
                (
                    png: try ImageCodec.encodePNG(
                        renderer.render(recipe, scale: scale), dpi: StripExport.dpi
                    ),
                    pdf: try renderer.renderPDF(recipe, photoDPI: StripExport.pdfPhotoDPI)
                )
            }.value

            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.png, .pdf], owner: nil)
            pasteboard.setData(flavours.png, forType: .png)
            pasteboard.setData(flavours.pdf, forType: .pdf)
            confirmCopy()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Two strips on a 4x6 sheet, which is the stock a booth prints on: one
    /// sheet, one cut, two keepsakes.
    func printStrip() async {
        guard let strip else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let renderer = self.renderer
            let recipe = strip.recipe
            let layout = SheetLayout()
            let resolved = try await Task.detached(priority: .userInitiated) {
                try renderer.resolve(recipe, photoDPI: StripExport.pdfPhotoDPI)
            }.value

            let operation = NSPrintOperation(
                view: StripPrintView(strip: resolved, layout: layout),
                printInfo: StripExport.printInfo(pageSize: layout.pageSize)
            )
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.run()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmCopy() {
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    /// The save panel the exports share, so they cannot drift on naming or on
    /// what a cancel does.
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
