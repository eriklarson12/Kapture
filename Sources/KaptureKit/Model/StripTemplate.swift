import CoreGraphics
import Foundation

/// A strip layout expressed in points, where one point is 1/72 inch. Geometry is
/// resolution-independent: the renderer scales the whole canvas by a factor
/// chosen at draw time, so a single template serves both the on-screen preview
/// and a 300 dpi print export.
public struct StripTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var frameCount: Int
    public var canvasSize: CGSize
    /// Border thickness on all four sides.
    public var outerInset: CGFloat
    /// Vertical space between adjacent photos.
    public var gutter: CGFloat
    /// Reserved strip along the bottom for a caption or date.
    public var footerHeight: CGFloat
    public var cornerRadius: CGFloat
    public var background: RGBA
    public var foreground: RGBA
    /// Caption size in points. 9pt in a 30pt band prints legibly at 300 dpi.
    public var captionFontSize: CGFloat
    public var captionAlignment: CaptionAlignment

    public init(
        id: String,
        name: String,
        frameCount: Int,
        canvasSize: CGSize,
        outerInset: CGFloat,
        gutter: CGFloat,
        footerHeight: CGFloat,
        cornerRadius: CGFloat = 0,
        background: RGBA = .paper,
        foreground: RGBA = .ink,
        captionFontSize: CGFloat = 9,
        captionAlignment: CaptionAlignment = .center
    ) {
        self.id = id
        self.name = name
        self.frameCount = frameCount
        self.canvasSize = canvasSize
        self.outerInset = outerInset
        self.gutter = gutter
        self.footerHeight = footerHeight
        self.cornerRadius = cornerRadius
        self.background = background
        self.foreground = foreground
        self.captionFontSize = captionFontSize
        self.captionAlignment = captionAlignment
    }

    /// False when the chrome leaves no room for the photos it claims to hold.
    public var isValid: Bool {
        frameCount > 0
            && canvasSize.width > 0
            && canvasSize.height > 0
            && photoHeight > 0
            && photoWidth > 0
    }

    public var photoWidth: CGFloat {
        canvasSize.width - outerInset * 2
    }

    /// The aspect every photo is cropped to. The live preview must be framed to
    /// this, or the subject composes against the window while the strip uses
    /// something narrower and the difference is lost with no warning.
    public var photoAspect: CGFloat {
        photoHeight > 0 ? photoWidth / photoHeight : 1
    }

    public var photoHeight: CGFloat {
        guard frameCount > 0 else { return 0 }
        let chrome = outerInset * 2 + footerHeight + gutter * CGFloat(frameCount - 1)
        return (canvasSize.height - chrome) / CGFloat(frameCount)
    }

    /// Photo frames in CoreGraphics coordinates, whose origin is bottom-left.
    /// Element 0 is the first shot and sits at the top of the strip.
    public func photoRects() -> [CGRect] {
        guard isValid else { return [] }
        let height = photoHeight
        return (0..<frameCount).map { index in
            let fromBottom = CGFloat(frameCount - 1 - index)
            return CGRect(
                x: outerInset,
                y: outerInset + footerHeight + fromBottom * (height + gutter),
                width: photoWidth,
                height: height
            )
        }
    }

    /// The footer band, empty when the template reserves no room for one.
    public func footerRect() -> CGRect {
        guard isValid, footerHeight > 0 else { return .zero }
        return CGRect(x: outerInset, y: outerInset, width: photoWidth, height: footerHeight)
    }

    /// A copy with the style's set fields applied. Resolving overrides here is
    /// what lets `StripRenderer` keep taking a finished template and never
    /// learn that overrides exist.
    public func applying(_ style: StripStyle?) -> StripTemplate {
        guard let style else { return self }
        var resolved = self
        if let background = style.background { resolved.background = background }
        if let foreground = style.foreground { resolved.foreground = foreground }
        if let outerInset = style.outerInset { resolved.outerInset = outerInset }
        if let cornerRadius = style.cornerRadius { resolved.cornerRadius = cornerRadius }
        if let captionFontSize = style.captionFontSize { resolved.captionFontSize = captionFontSize }
        if let captionAlignment = style.captionAlignment { resolved.captionAlignment = captionAlignment }
        return resolved
    }

    /// Points are 1/72 inch, so this is the render scale that lands the canvas
    /// at `dpi`. The classic 2x6 strip at 300 dpi is 600x1800 pixels.
    public func scale(forDPI dpi: CGFloat) -> CGFloat {
        dpi / 72
    }

    /// Output pixel dimensions at a given dpi, rounded the way the renderer rounds.
    public func pixelSize(atDPI dpi: CGFloat) -> CGSize {
        let factor = scale(forDPI: dpi)
        return CGSize(
            width: (canvasSize.width * factor).rounded(),
            height: (canvasSize.height * factor).rounded()
        )
    }
}
