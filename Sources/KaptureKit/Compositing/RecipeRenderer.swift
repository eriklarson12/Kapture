import CoreGraphics
import Foundation

public enum RecipeRenderError: Error, Equatable {
    case unknownTemplate(String)
}

/// Turns a stored recipe back into an image: resolve the template, load the
/// frames, composite. This is the payoff for ADR-003 — nothing was baked, so a
/// strip can be re-rendered at any size, with any template, forever.
///
/// Per-strip overrides in `recipe.style` are resolved here, so `StripRenderer`
/// keeps taking a finished template. Filters are recorded but not yet applied;
/// that is item 2.4.
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
        let frames = try store.loadFrames(for: recipe)
        return try StripRenderer().render(
            frames: frames,
            template: template,
            scale: scale,
            mirrored: recipe.mirrorOutput,
            caption: recipe.caption
        )
    }
}
