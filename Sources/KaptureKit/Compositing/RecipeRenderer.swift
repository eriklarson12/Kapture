import CoreGraphics
import Foundation

public enum RecipeRenderError: Error, Equatable {
    case unknownTemplate(String)
}

/// The payoff for ADR-003 — nothing was baked, so a strip can be re-rendered
/// at any size, with any template, forever.
public struct RecipeRenderer: Sendable {
    private let store: StripStore
    private let templates: [String: StripTemplate]
    private let masks: PersonMaskStore
    private let faces: FaceStore

    public init(
        store: StripStore,
        templates: [String: StripTemplate] = BuiltInTemplates.byID,
        masks: PersonMaskStore = PersonMaskStore(),
        faces: FaceStore = FaceStore()
    ) {
        self.store = store
        self.templates = templates
        self.masks = masks
        self.faces = faces
    }

    public func template(for recipe: StripRecipe) throws -> StripTemplate {
        guard let template = templates[recipe.templateID] else {
            throw RecipeRenderError.unknownTemplate(recipe.templateID)
        }
        return template
    }

    /// `photoDPI` shrinks each frame to what its photo rect needs at that
    /// resolution; nil leaves frames alone, which an on-screen render wants.
    public func resolve(_ recipe: StripRecipe, photoDPI: CGFloat? = nil) throws -> ResolvedStrip {
        let template = try template(for: recipe).applying(recipe.style)
        var frames = try photographs(for: recipe, photoAspect: template.photoAspect)
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

    public func renderSheetPDF(
        _ recipe: StripRecipe, layout: SheetLayout = SheetLayout(), photoDPI: CGFloat = 300
    ) throws -> Data {
        try PDFRenderer.sheet(resolve(recipe, photoDPI: photoDPI), layout: layout)
    }

    /// Style is resolved before `photoAspect` is read — a strip with
    /// `outerInset` overridden must not frame differently from its template.
    public func renderFrames(_ recipe: StripRecipe, height: CGFloat) throws -> [CGImage] {
        let template = try template(for: recipe).applying(recipe.style)
        let size = Self.evenSize(height: height, aspect: template.photoAspect)
        return try photographs(for: recipe, photoAspect: template.photoAspect).map { frame in
            try StripRenderer.photo(frame, size: size, mirrored: recipe.mirrorOutput)
        }
    }

    /// Order is not a preference: filtering first leaves the backdrop
    /// grain-free — a cut-out's tell — so mask and crop read the unfiltered frame.
    private func photographs(
        for recipe: StripRecipe, photoAspect: CGFloat
    ) throws -> [CGImage] {
        let images = try store.loadFrames(for: recipe)
        let composited = try composited(images, for: recipe)
        guard recipe.faceFraming == true else { return composited }
        return zip(recipe.frameIDs, zip(images, composited)).map { frameID, pair in
            let (stored, shown) = pair
            guard let focus = faces.focus(for: stored, id: frameID) else { return shown }
            return FaceFramer.cropped(shown, aspect: photoAspect, focus: focus)
        }
    }

    private func composited(_ images: [CGImage], for recipe: StripRecipe) throws -> [CGImage] {
        func filtered(_ image: CGImage) -> CGImage {
            FilterRenderer.apply(recipe.filter, to: image)
        }

        guard let background = recipe.backdrop else { return images.map(filtered) }

        var asset: CGImage?
        if case .image(let assetID) = background {
            // A gone backdrop picture leaves the photograph — unlike a
            // missing paper picture, which refuses the strip entirely.
            guard let loaded = try? store.loadAsset(assetID, in: recipe.id) else {
                return images.map(filtered)
            }
            asset = loaded
        }

        // Painted once per distinct frame size, not per frame. Keyed by ints
        // because `CGSize` isn't `Hashable` until macOS 15, and this target is 14.
        var rasters: [Pixels: CGImage] = [:]

        return zip(recipe.frameIDs, images).map { frameID, image in
            guard let mask = masks.mask(for: image, id: frameID) else { return filtered(image) }
            let size = Pixels(width: image.width, height: image.height)
            let raster: CGImage
            if let painted = rasters[size] {
                raster = painted
            } else if let painted = try? StripRenderer.backdrop(
                background,
                size: CGSize(width: image.width, height: image.height),
                image: asset
            ) {
                rasters[size] = painted
                raster = painted
            } else {
                return filtered(image)
            }
            return filtered(BackdropRenderer.composite(image, over: raster, mask: mask))
        }
    }

    private struct Pixels: Hashable {
        let width: Int
        let height: Int
    }

    /// Rounded to even numbers — H.264 rejects odd dimensions, and a GIF and
    /// movie of the same strip must not disagree on size.
    static func evenSize(height: CGFloat, aspect: CGFloat) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded() * 2) }
        return CGSize(width: even(height * aspect), height: even(height))
    }

    /// Resolves the background asset so `StripRenderer` stays I/O-free. Nil
    /// for every background that is just colour.
    private func backgroundImage(
        for recipe: StripRecipe, template: StripTemplate
    ) throws -> CGImage? {
        guard case .image(let assetID) = template.background else { return nil }
        return try store.loadAsset(assetID, in: recipe.id)
    }
}
