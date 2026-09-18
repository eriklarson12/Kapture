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

    /// Scale 1 is preview geometry; `template.scale(forDPI: 300)` is a print.
    public func render(_ recipe: StripRecipe, scale: CGFloat = 1) throws -> CGImage {
        let template = try template(for: recipe).applying(recipe.style)
        let frames = try store.loadFrames(for: recipe).map {
            FilterRenderer.apply(recipe.filter, to: $0)
        }
        return try StripRenderer().render(
            frames: frames,
            template: template,
            backgroundImage: try backgroundImage(for: recipe, template: template),
            scale: scale,
            mirrored: recipe.mirrorOutput,
            caption: recipe.caption
        )
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
