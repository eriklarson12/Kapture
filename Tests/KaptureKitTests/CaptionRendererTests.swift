import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("CaptionRenderer")
struct CaptionRendererTests {
    private func render(
        caption: String?,
        template: StripTemplate = BuiltInTemplates.classicStrip
    ) throws -> CGImage {
        try StripRenderer().render(
            frames: TestImage.frames(template.frameCount),
            template: template,
            caption: caption
        )
    }

    /// Bitmap row 0 is the top of the canvas, while `footerRect()` is in
    /// CoreGraphics coordinates whose origin is bottom-left. The band is
    /// therefore measured down from the far edge.
    private func footerRows(_ image: CGImage, _ template: StripTemplate) -> Range<Int> {
        let rect = template.footerRect()
        return (image.height - Int(rect.maxY))..<(image.height - Int(rect.minY))
    }

    /// Columns of every dark pixel inside the footer band. Ink is the only dark
    /// thing there: the band is paper, and no photo reaches it.
    private func inkColumns(_ image: CGImage, _ template: StripTemplate) -> [Int] {
        let pixels = TestImage.pixels(image)
        var columns: [Int] = []
        for row in footerRows(image, template) {
            for x in 0..<image.width where pixels[row * image.width * 4 + x * 4] < 128 {
                columns.append(x)
            }
        }
        return columns
    }

    @Test("a caption puts ink in the footer band")
    func captionDrawsInk() throws {
        let template = BuiltInTemplates.classicStrip
        let strip = try render(caption: "Hello", template: template)
        #expect(inkColumns(strip, template).isEmpty == false)
    }

    @Test("without a caption the footer band is bare paper")
    func noCaptionLeavesBandEmpty() throws {
        let template = BuiltInTemplates.classicStrip
        #expect(try inkColumns(render(caption: nil), template).isEmpty)
        #expect(try inkColumns(render(caption: ""), template).isEmpty)
        // Whitespace is not a caption; it would otherwise reserve a band of
        // nothing and read as a rendering bug.
        #expect(try inkColumns(render(caption: "   "), template).isEmpty)
    }

    @Test("alignment moves the caption across the band")
    func alignmentShiftsInk() throws {
        let classic = BuiltInTemplates.classicStrip
        func centroid(_ alignment: CaptionAlignment) throws -> Double {
            let template = classic.applying(StripStyle(captionAlignment: alignment))
            let columns = inkColumns(try render(caption: "Kapture", template: template), template)
            #expect(columns.isEmpty == false)
            return Double(columns.reduce(0, +)) / Double(columns.count)
        }

        let leading = try centroid(.leading)
        let centre = try centroid(.center)
        let trailing = try centroid(.trailing)
        #expect(leading < centre)
        #expect(centre < trailing)
    }

    @Test("an over-long caption is truncated inside the band")
    func longCaptionStaysInside() throws {
        let template = BuiltInTemplates.classicStrip
        let strip = try render(
            caption: String(repeating: "Kapture photobooth ", count: 12),
            template: template
        )
        let columns = inkColumns(strip, template)
        #expect(columns.isEmpty == false)

        // The band spans x 8..136. Two pixels of slack for glyph ink that
        // overhangs its typographic advance.
        let rect = template.footerRect()
        #expect(columns.min()! >= Int(rect.minX) - 2)
        #expect(columns.max()! <= Int(rect.maxX) + 2)
    }

    @Test("a template with no footer draws no caption")
    func noFooterNoCaption() throws {
        var template = BuiltInTemplates.classicStrip
        template.footerHeight = 0
        let strip = try render(caption: "Hello", template: template)
        #expect(template.footerRect() == .zero)
        #expect(strip.height == Int(template.canvasSize.height))
    }
}
