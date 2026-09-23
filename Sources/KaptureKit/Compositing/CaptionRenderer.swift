import CoreGraphics
import CoreText
import Foundation

/// Separate from `StripRenderer` because text is drawn as glyphs at the
/// output scale, so a 300 dpi export gets 300 dpi type, not an enlarged preview.
enum CaptionRenderer {
    /// No-op when there is no text or no band to put it in.
    static func draw(
        _ caption: String,
        in rect: CGRect,
        template: StripTemplate,
        context: CGContext
    ) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !rect.isEmpty else { return }
        guard let font = CTFontCreateUIFontForLanguage(.system, template.captionFontSize, nil) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: template.foreground.cgColor,
        ]
        let full = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        // A caption wider than the strip would print running off the paper, so
        // it is cut with an ellipsis instead. Visible truncation beats silent.
        let line = truncated(full, to: rect.width, attributes: attributes)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        // Centre the ascent-to-descent box in the band rather than resting the
        // baseline on its floor, which would sit the text visibly low.
        let baselineY = rect.midY - (ascent + descent) / 2 + descent
        let x = switch template.captionAlignment {
        case .leading: rect.minX
        case .center: rect.midX - width / 2
        case .trailing: rect.maxX - width
        }

        context.saveGState()
        context.textPosition = CGPoint(x: x, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func truncated(
        _ line: CTLine,
        to width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CTLine {
        guard CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) > width else { return line }
        let ellipsis = CTLineCreateWithAttributedString(
            NSAttributedString(string: "\u{2026}", attributes: attributes)
        )
        return CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line
    }
}
