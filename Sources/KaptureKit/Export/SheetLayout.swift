import CoreGraphics
import Foundation

/// A page with one or more copies of a strip laid out on it for cutting.
/// Pure geometry in points, so what a printer does is asserted in tests.
public struct SheetLayout: Equatable, Sendable {
    /// 4x6 inches in points. A 2x6 strip tiles it exactly twice, which is why
    /// photobooths print on this stock: one sheet, two strips, one cut.
    public static let fourBySix = CGSize(width: 288, height: 432)

    public var pageSize: CGSize

    public init(pageSize: CGSize = SheetLayout.fourBySix) {
        self.pageSize = pageSize
    }

    /// Where each copy of `template` lands, in points, bottom-left origin.
    /// A template too large for the page is scaled down uniformly, never cropped.
    public func placements(for template: StripTemplate) -> [CGRect] {
        let size = template.canvasSize
        guard size.width > 0, size.height > 0,
              pageSize.width > 0, pageSize.height > 0 else { return [] }

        let fit = min(1, min(pageSize.width / size.width, pageSize.height / size.height))
        let scaled = CGSize(width: size.width * fit, height: size.height * fit)
        // The epsilon is what stops a 2x6 on a 4x6 landing on 1.9999999 and
        // printing one strip on a sheet that holds two.
        let copies = max(1, Int(pageSize.width / scaled.width + 1e-9))

        let originX = (pageSize.width - scaled.width * CGFloat(copies)) / 2
        let originY = (pageSize.height - scaled.height) / 2
        return (0..<copies).map { index in
            CGRect(
                x: originX + scaled.width * CGFloat(index),
                y: originY,
                width: scaled.width,
                height: scaled.height
            )
        }
    }

    /// Draws `strip` at each placement. Shared by the PDF sheet and the print
    /// job, so a printed sheet can't be laid out differently from a saved one.
    public func draw(_ strip: ResolvedStrip, into context: CGContext) throws {
        let canvas = strip.template.canvasSize
        guard canvas.width > 0, canvas.height > 0 else { return }
        for rect in placements(for: strip.template) {
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / canvas.width, y: rect.height / canvas.height)
            try strip.draw(into: context)
        }
    }
}
