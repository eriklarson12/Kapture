import CoreGraphics
import Foundation

/// Where a caption sits in the footer band.
///
/// Defined here rather than reusing SwiftUI's `TextAlignment`, which the engine
/// may not import. The raw values are what reach `recipe.json`.
public enum CaptionAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing

    public var displayName: String {
        switch self {
        case .leading: "Left"
        case .center: "Centre"
        case .trailing: "Right"
        }
    }
}

/// Per-strip overrides on top of a template.
///
/// Every field is optional and `nil` means "follow the template". That is what
/// keeps a template edit meaningful: a field the user never touched still moves
/// when its template moves, which is the whole of roadmap 4.4. Storing resolved
/// values here instead would freeze every strip at the moment it was shot.
public struct StripStyle: Codable, Equatable, Sendable {
    public var background: StripBackground?
    public var foreground: RGBA?
    public var outerInset: CGFloat?
    public var cornerRadius: CGFloat?
    public var captionFontSize: CGFloat?
    public var captionAlignment: CaptionAlignment?

    public init(
        background: StripBackground? = nil,
        foreground: RGBA? = nil,
        outerInset: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        captionFontSize: CGFloat? = nil,
        captionAlignment: CaptionAlignment? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.outerInset = outerInset
        self.cornerRadius = cornerRadius
        self.captionFontSize = captionFontSize
        self.captionAlignment = captionAlignment
    }

    /// True when nothing is overridden, so a caller can store `nil` rather than
    /// a style that says nothing.
    public var isEmpty: Bool {
        background == nil
            && foreground == nil
            && outerInset == nil
            && cornerRadius == nil
            && captionFontSize == nil
            && captionAlignment == nil
    }
}
