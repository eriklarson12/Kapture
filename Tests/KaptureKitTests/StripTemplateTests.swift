import CoreGraphics
import Testing
@testable import KaptureKit

@Suite("StripTemplate layout")
struct StripTemplateTests {
    @Test("emits one rect per frame")
    func rectCount() {
        let rects = BuiltInTemplates.classicStrip.photoRects()
        #expect(rects.count == BuiltInTemplates.classicStrip.frameCount)
    }

    @Test("orders rects top to bottom, first shot highest")
    func ordering() {
        let rects = BuiltInTemplates.classicStrip.photoRects()
        for (upper, lower) in zip(rects, rects.dropFirst()) {
            #expect(upper.minY > lower.minY)
        }
    }

    /// Row-major, and element 0 is the top-left. Frames are zipped against
    /// this order, so reversing it would silently shuffle the photos.
    @Test("a grid fills row by row, first shot top-left")
    func gridOrder() {
        let rects = BuiltInTemplates.gridQuad.photoRects()
        #expect(rects.count == 4)
        #expect(rects[0].minX < rects[1].minX)
        #expect(rects[0].minY == rects[1].minY)
        #expect(rects[2].minY < rects[0].minY)
        #expect(rects[2].minX == rects[0].minX)
        #expect(rects[3].minX == rects[1].minX)
        #expect(rects[3].minY == rects[2].minY)
    }

    @Test("a grid divides the width between its columns")
    func gridWidth() {
        let template = BuiltInTemplates.gridQuad
        let expectedWidth: CGFloat = 123   // (288 - 16*2 - 10) / 2
        let expectedHeight: CGFloat = 177  // (432 - 16*2 - 36 - 10) / 2
        #expect(template.rows == 2)
        #expect(template.contentWidth == 256)
        #expect(template.photoWidth == expectedWidth)
        #expect(template.photoHeight == expectedHeight)
    }

    /// The caption band spans the paper, not one column. Reusing `photoWidth`
    /// would shrink the footer to half the strip once a second column exists.
    @Test("the footer spans the paper whatever the column count")
    func gridFooter() {
        let template = BuiltInTemplates.gridQuad
        #expect(template.footerRect().width == template.contentWidth)
        #expect(template.footerRect().width > template.photoWidth)
        for rect in template.photoRects() {
            #expect(rect.minY >= template.footerRect().maxY)
        }
    }

    @Test("a grid at 300 dpi is the page it says it is")
    func gridPrintSize() {
        #expect(BuiltInTemplates.gridQuad.pixelSize(atDPI: 300) == CGSize(width: 1200, height: 1800))
    }

    /// `TemplateImport` refuses this, so it can only arrive from code. It must
    /// still lay out every photo rather than divide by zero or lose a row.
    @Test("a ragged grid still emits one rect per photo")
    func raggedGrid() {
        let ragged = StripTemplate(
            id: "ragged", name: "Ragged", frameCount: 5, columns: 2,
            canvasSize: CGSize(width: 288, height: 432),
            outerInset: 16, gutter: 10, footerHeight: 36
        )
        #expect(ragged.rows == 3)
        #expect(ragged.photoRects().count == 5)
        let canvas = CGRect(origin: .zero, size: ragged.canvasSize)
        for rect in ragged.photoRects() {
            #expect(canvas.contains(rect))
        }
    }

    @Test("a template with no columns is invalid rather than fatal")
    func zeroColumns() {
        let none = StripTemplate(
            id: "none", name: "None", frameCount: 4, columns: 0,
            canvasSize: CGSize(width: 144, height: 432),
            outerInset: 8, gutter: 6, footerHeight: 30
        )
        #expect(none.rows == 0)
        #expect(none.photoWidth == 0)
        #expect(none.isValid == false)
        #expect(none.photoRects().isEmpty)
    }

    @Test("keeps every rect inside the canvas")
    func withinCanvas() {
        for template in BuiltInTemplates.all {
            let canvas = CGRect(origin: .zero, size: template.canvasSize)
            for rect in template.photoRects() {
                #expect(canvas.contains(rect))
            }
        }
    }

    /// Stated per row now that a grid exists: two photos side by side share a
    /// row, so "every rect is above the next" is only true down a column.
    @Test("never overlaps two photos")
    func noOverlap() {
        for template in BuiltInTemplates.all {
            let rects = template.photoRects()
            for (first, second) in pairs(of: rects) {
                #expect(first.intersects(second) == false)
            }
        }
    }

    private func pairs(of rects: [CGRect]) -> [(CGRect, CGRect)] {
        rects.indices.flatMap { index in
            rects[(index + 1)...].map { (rects[index], $0) }
        }
    }

    @Test("reserves the footer band below the lowest photo")
    func footerReserved() {
        let template = BuiltInTemplates.classicStrip
        let lowest = template.photoRects().last!
        #expect(lowest.minY >= template.outerInset + template.footerHeight)
        #expect(template.footerRect().maxY <= lowest.minY)
    }

    @Test("deriving a template keeps the layout and changes only the identity")
    func derived() {
        let base = BuiltInTemplates.wideStrip
        let copy = base.derived(name: "Cream Wide")
        #expect(copy.name == "Cream Wide")
        #expect(copy.id != base.id)
        #expect(copy.derived(name: "Cream Wide").id != copy.id)

        var renamed = copy
        renamed.id = base.id
        renamed.name = base.name
        #expect(renamed == base)
    }

    @Test("rejects a template whose chrome leaves no room")
    func invalidTemplate() {
        let crushed = StripTemplate(
            id: "crushed",
            name: "Crushed",
            frameCount: 4,
            canvasSize: CGSize(width: 144, height: 40),
            outerInset: 8,
            gutter: 6,
            footerHeight: 30
        )
        #expect(crushed.isValid == false)
        #expect(crushed.photoRects().isEmpty)
    }

    @Test("classic strip is 600x1800 at 300 dpi")
    func printSize() {
        let size = BuiltInTemplates.classicStrip.pixelSize(atDPI: 300)
        #expect(size == CGSize(width: 600, height: 1800))
    }

    @Test("photo aspect is the shape the preview must be framed to")
    func photoAspect() {
        let template = BuiltInTemplates.classicStrip
        #expect(template.photoWidth == 128)
        #expect(template.photoHeight == 92)
        #expect(abs(template.photoAspect - 128.0 / 92.0) < 0.0001)
        // Narrower than a 16:9 camera, which is exactly why the viewport has to
        // be constrained to it rather than to the window.
        #expect(template.photoAspect < 16.0 / 9.0)
    }
}
