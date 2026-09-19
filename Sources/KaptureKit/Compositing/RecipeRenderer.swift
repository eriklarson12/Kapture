import CoreGraphics
import Foundation

public enum RecipeRenderError: Error, Equatable {
    case unknownTemplate(String)
}

/// Turns a stored recipe back into an image: resolve the template, load the
/// frames, composite. This is the payoff for ADR-003 — nothing was baked, so a
/// strip can be re-rendered at any size, with any template, forever.
///
/// Per-strip overrides in `recipe.style` are resolved here, and the recorded
/// filter is applied here, so `StripRenderer` keeps taking finished frames and
/// a finished template and stays pure geometry.
public struct RecipeRenderer: Sendable {
    private let store: StripStore
    private let templates: [String: StripTemplate]

    public init(store: StripStore, templates: [String: StripTemplate] = BuiltInTemplates.byID) {
        self.store = store
        self.templates = templates
    }

    public func template(for recipe: StripRecipe) throws -> StripTemplate {
        guard let template = templates[recipe.templateID] else {
            throw RecipeRenderError.unknownTemplate(recipe.templateID)
        }
        return template
    }

    /// Everything the recipe points at, loaded once: the template with the
    /// strip's overrides applied, the frames filtered, and the background
    /// picture if it has one.
    ///
    /// `photoDPI`, when given, shrinks each frame to the size its photo rect
    /// needs at that resolution. A stored frame is 1920x1080 and a photo band
    /// on the classic strip at 300 dpi is about 534x384, so a PDF of a real
    /// strip is 12.6 MB with the originals embedded and 2.1 MB without. Nil
    /// leaves the frames alone, which is what an on-screen render wants.
    public func resolve(_ recipe: StripRecipe, photoDPI: CGFloat? = nil) throws -> ResolvedStrip {
        let template = try template(for: recipe).applying(recipe.style)
        var frames = try store.loadFrames(for: recipe).map {
            FilterRenderer.apply(recipe.filter, to: $0)
        }
        if let photoDPI {
            let scale = template.scale(forDPI: photoDPI)
            let cover = CGSize(
                width: template.photoWidth * scale,
                height: template.photoHeight * scale
            )
            frames = frames.map { StripRenderer.downscaled($0, covering: cover) }
        }
        return ResolvedStrip(
            template: template,
            frames: frames,
            backgroundImage: try backgroundImage(for: recipe, template: template),
            mirrored: recipe.mirrorOutput,
            caption: recipe.caption
        )
    }

    /// Scale 1 is preview geometry; `template.scale(forDPI: 300)` is a print.
    public func render(_ recipe: StripRecipe, scale: CGFloat = 1) throws -> CGImage {
        try resolve(recipe).render(scale: scale)
    }

    /// The strip as a single page at its own size in points, so a 2x6 strip is
    /// a document that measures two inches by six wherever it is opened.
    public func renderPDF(_ recipe: StripRecipe, photoDPI: CGFloat = 300) throws -> Data {
        try PDFRenderer.page(resolve(recipe, photoDPI: photoDPI))
    }

    /// The strip tiled onto a sheet for printing and cutting.
    public func renderSheetPDF(
        _ recipe: StripRecipe, layout: SheetLayout = SheetLayout(), photoDPI: CGFloat = 300
    ) throws -> Data {
        try PDFRenderer.sheet(resolve(recipe, photoDPI: photoDPI), layout: layout)
    }

    /// The recipe's photos as standalone images: filtered, mirrored, and
    /// cropped to the aspect the strip crops them to. Both animation exports
    /// consume this, so a GIF cannot drift from the strip it came from.
    ///
    /// The style is resolved before `photoAspect` is read. A strip overriding
    /// `outerInset` crops its photos differently from its own template, and an
    /// animation that ignored the override would be framed differently from the
    /// paper it came from.
    public func renderFrames(_ recipe: StripRecipe, height: CGFloat) throws -> [CGImage] {
        let template = try template(for: recipe).applying(recipe.style)
        let size = Self.evenSize(height: height, aspect: template.photoAspect)
        return try store.loadFrames(for: recipe).map { frame in
            try StripRenderer.photo(
                FilterRenderer.apply(recipe.filter, to: frame),
                size: size,
                mirrored: recipe.mirrorOutput
            )
        }
    }

    /// `height` by `height * aspect`, both rounded to even numbers. H.264
    /// rejects odd dimensions, and there is no reason for a GIF and a movie of
    /// the same strip to disagree on size.
    static func evenSize(height: CGFloat, aspect: CGFloat) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded() * 2) }
        return CGSize(width: even(height * aspect), height: even(height))
    }

    /// Resolves a background asset out of the strip's own package, so
    /// `StripRenderer` keeps doing no I/O. Nil for every background that is
    /// just colour, which is all of them until someone picks a picture.
    private func backgroundImage(
        for recipe: StripRecipe, template: StripTemplate
    ) throws -> CGImage? {
        guard case .image(let assetID) = template.background else { return nil }
        return try store.loadAsset(assetID, in: recipe.id)
    }
}
