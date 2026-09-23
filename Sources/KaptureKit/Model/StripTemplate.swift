import CoreGraphics
import Foundation

/// One point is 1/72 inch; the renderer scales the whole canvas at draw
/// time, so one template serves both the preview and a 300 dpi export.
public struct StripTemplate: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var frameCount: Int
    /// 1 is a stack, 2 a grid two across — fills row-major, so element 0 is
    /// the top-left photo, matching `photoRects()`.
    public var columns: Int
    public var canvasSize: CGSize
    /// Border thickness on all four sides.
    public var outerInset: CGFloat
    /// A grid's horizontal gap and a stack's vertical gap are the same
    /// visual thing, so one field, not two kept equal by hand.
    public var gutter: CGFloat
    /// Reserved strip along the bottom for a caption or date.
    public var footerHeight: CGFloat
    public var cornerRadius: CGFloat
    public var background: StripBackground
    public var foreground: RGBA
    /// Caption size in points. 9pt in a 30pt band prints legibly at 300 dpi.
    public var captionFontSize: CGFloat
    public var captionAlignment: CaptionAlignment

    public init(
        id: String,
        name: String,
        frameCount: Int,
        columns: Int = 1,
        canvasSize: CGSize,
        outerInset: CGFloat,
        gutter: CGFloat,
        footerHeight: CGFloat,
        cornerRadius: CGFloat = 0,
        background: StripBackground = .solid(.paper),
        foreground: RGBA = .ink,
        captionFontSize: CGFloat = 9,
        captionAlignment: CaptionAlignment = .center
    ) {
        self.id = id
        self.name = name
        self.frameCount = frameCount
        self.columns = columns
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
            && columns > 0
            && canvasSize.width > 0
            && canvasSize.height > 0
            && photoHeight > 0
            && photoWidth > 0
    }

    /// Ceiling division, so a template that skipped `TemplateImport.validate`
    /// still lays out every photo it claims, not dropping the last row.
    public var rows: Int {
        guard columns > 0 else { return 0 }
        return (frameCount + columns - 1) / columns
    }

    /// The full width inside the border: one photo wide in a stack, and the
    /// band a caption is laid out in whatever the column count.
    public var contentWidth: CGFloat {
        canvasSize.width - outerInset * 2
    }

    public var photoWidth: CGFloat {
        guard columns > 0 else { return 0 }
        return (contentWidth - gutter * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// The live preview must be framed to this, or the subject composes
    /// against a window that crops differently than the strip does.
    public var photoAspect: CGFloat {
        photoHeight > 0 ? photoWidth / photoHeight : 1
    }

    public var photoHeight: CGFloat {
        let rowCount = rows
        guard rowCount > 0 else { return 0 }
        let chrome = outerInset * 2 + footerHeight + gutter * CGFloat(rowCount - 1)
        return (canvasSize.height - chrome) / CGFloat(rowCount)
    }

    /// Photo frames in CoreGraphics coordinates, whose origin is bottom-left.
    /// Element 0 is the first shot: the top of a stack, the top-left of a grid.
    public func photoRects() -> [CGRect] {
        guard isValid else { return [] }
        let width = photoWidth
        let height = photoHeight
        let rowCount = rows
        return (0..<frameCount).map { index in
            let fromBottom = CGFloat(rowCount - 1 - index / columns)
            return CGRect(
                x: outerInset + CGFloat(index % columns) * (width + gutter),
                y: outerInset + footerHeight + fromBottom * (height + gutter),
                width: width,
                height: height
            )
        }
    }

    /// The footer band, empty when the template reserves no room for one.
    public func footerRect() -> CGRect {
        guard isValid, footerHeight > 0 else { return .zero }
        return CGRect(x: outerInset, y: outerInset, width: contentWidth, height: footerHeight)
    }

    /// Resolving overrides here is what lets `StripRenderer` keep taking a
    /// finished template and never learn that overrides exist.
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

    /// The id is always fresh — the file is the identity, so saving twice
    /// gives two templates, and updating one means re-importing its file.
    public func derived(name: String) -> StripTemplate {
        var copy = self
        copy.id = "user-\(UUID().uuidString.lowercased())"
        copy.name = name
        return copy
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

extension StripTemplate: Codable {
    /// `CGSize` encodes itself as `[144, 432]`, a coin flip between width
    /// and height in a file someone edits — named width/height avoids that.
    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, frameCount, columns, canvasSize
        case outerInset, gutter, footerHeight, cornerRadius
        case background, foreground, captionFontSize, captionAlignment
    }

    private enum SizeKeys: String, CodingKey {
        case width, height
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            frameCount: try container.decode(Int.self, forKey: .frameCount),
            columns: try container.decodeIfPresent(Int.self, forKey: .columns) ?? 1,
            canvasSize: try Self.decodeSize(from: container),
            outerInset: try container.decode(CGFloat.self, forKey: .outerInset),
            gutter: try container.decode(CGFloat.self, forKey: .gutter),
            footerHeight: try container.decode(CGFloat.self, forKey: .footerHeight),
            cornerRadius: try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0,
            background: try container.decodeIfPresent(StripBackground.self, forKey: .background)
                ?? .solid(.paper),
            foreground: try container.decodeIfPresent(RGBA.self, forKey: .foreground) ?? .ink,
            captionFontSize: try container.decodeIfPresent(CGFloat.self, forKey: .captionFontSize)
                ?? 9,
            captionAlignment: try container.decodeIfPresent(
                CaptionAlignment.self, forKey: .captionAlignment
            ) ?? .center
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(columns, forKey: .columns)
        var size = container.nestedContainer(keyedBy: SizeKeys.self, forKey: .canvasSize)
        try size.encode(canvasSize.width, forKey: .width)
        try size.encode(canvasSize.height, forKey: .height)
        try container.encode(outerInset, forKey: .outerInset)
        try container.encode(gutter, forKey: .gutter)
        try container.encode(footerHeight, forKey: .footerHeight)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(background, forKey: .background)
        try container.encode(foreground, forKey: .foreground)
        try container.encode(captionFontSize, forKey: .captionFontSize)
        try container.encode(captionAlignment, forKey: .captionAlignment)
    }

    /// Reads either named width/height or the `[width, height]` pair
    /// `CGSize` writes for itself, so another program's output still decodes.
    private static func decodeSize(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> CGSize {
        if let size = try? container.nestedContainer(keyedBy: SizeKeys.self, forKey: .canvasSize) {
            return CGSize(
                width: try size.decode(CGFloat.self, forKey: .width),
                height: try size.decode(CGFloat.self, forKey: .height)
            )
        }
        return try container.decode(CGSize.self, forKey: .canvasSize)
    }
}
