import CoreGraphics
import Foundation

/// A recipe with everything it points at already loaded: the template with its
/// overrides applied, the frames filtered, and the background picture if it has
/// one.
///
/// Exists so a caller that draws more than once resolves the recipe once. A
/// print job redraws its view whenever AppKit asks, and a sheet draws the same
/// strip twice; neither may go to disk inside a draw call.
public struct ResolvedStrip: Sendable {
    public let template: StripTemplate
    public let frames: [CGImage]
    public let backgroundImage: CGImage?
    public let mirrored: Bool
    public let caption: String?

    public init(
        template: StripTemplate,
        frames: [CGImage],
        backgroundImage: CGImage? = nil,
        mirrored: Bool = false,
        caption: String? = nil
    ) {
        self.template = template
        self.frames = frames
        self.backgroundImage = backgroundImage
        self.mirrored = mirrored
        self.caption = caption
    }

    public func draw(into context: CGContext) throws {
        try StripRenderer().draw(
            frames: frames,
            template: template,
            backgroundImage: backgroundImage,
            mirrored: mirrored,
            caption: caption,
            into: context
        )
    }

    public func render(scale: CGFloat = 1) throws -> CGImage {
        try StripRenderer().render(
            frames: frames,
            template: template,
            backgroundImage: backgroundImage,
            scale: scale,
            mirrored: mirrored,
            caption: caption
        )
    }
}
