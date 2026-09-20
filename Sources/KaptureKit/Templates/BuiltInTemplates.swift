import CoreGraphics
import Foundation

/// The shipped layouts. Custom templates are the same struct decoded from JSON,
/// so a user template is not a lesser citizen than a built-in one.
public enum BuiltInTemplates {
    /// The classic photobooth strip: 2x6 inches, four shots. Renders to
    /// 600x1800 pixels at 300 dpi.
    public static let classicStrip = StripTemplate(
        id: "classic-strip",
        name: "Classic Strip",
        frameCount: 4,
        canvasSize: CGSize(width: 144, height: 432),
        outerInset: 8,
        gutter: 6,
        footerHeight: 30
    )

    /// Three shots on the same 2x6 stock, for a taller frame.
    public static let tripleStrip = StripTemplate(
        id: "triple-strip",
        name: "Triple Strip",
        frameCount: 3,
        canvasSize: CGSize(width: 144, height: 432),
        outerInset: 8,
        gutter: 6,
        footerHeight: 30
    )

    /// Four shots on a 4x6 print, stacked with a wider border.
    public static let wideStrip = StripTemplate(
        id: "wide-strip",
        name: "Wide Strip",
        frameCount: 4,
        canvasSize: CGSize(width: 288, height: 432),
        outerInset: 16,
        gutter: 10,
        footerHeight: 36,
        cornerRadius: 4
    )

    /// Four shots as a 2x2 grid on a 4x6 print. One sheet, one print, no cut,
    /// where a 2x6 strip is printed twice and cut apart.
    ///
    /// Its photos are portrait where a strip's are landscape, so the live
    /// preview letterbox turns with it. That is the layout, not a fault.
    public static let gridQuad = StripTemplate(
        id: "grid-quad",
        name: "Quad Grid",
        frameCount: 4,
        columns: 2,
        canvasSize: CGSize(width: 288, height: 432),
        outerInset: 16,
        gutter: 10,
        footerHeight: 36,
        cornerRadius: 4
    )

    public static let all: [StripTemplate] = [classicStrip, tripleStrip, wideStrip, gridQuad]

    /// Keyed for `RecipeRenderer`, which resolves a recipe's `templateID`.
    /// Item 5.2 adds user templates by adding entries, not by adding a
    /// second lookup path.
    public static let byID: [String: StripTemplate] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static func template(id: String) -> StripTemplate? {
        all.first { $0.id == id }
    }
}
