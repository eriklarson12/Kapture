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

    @Test("keeps every rect inside the canvas")
    func withinCanvas() {
        for template in BuiltInTemplates.all {
            let canvas = CGRect(origin: .zero, size: template.canvasSize)
            for rect in template.photoRects() {
                #expect(canvas.contains(rect))
            }
        }
    }

    @Test("never overlaps adjacent photos")
    func noOverlap() {
        for template in BuiltInTemplates.all {
            let rects = template.photoRects()
            for (upper, lower) in zip(rects, rects.dropFirst()) {
                #expect(upper.minY >= lower.maxY)
            }
        }
    }

    @Test("reserves the footer band below the lowest photo")
    func footerReserved() {
        let template = BuiltInTemplates.classicStrip
        let lowest = template.photoRects().last!
        #expect(lowest.minY >= template.outerInset + template.footerHeight)
        #expect(template.footerRect().maxY <= lowest.minY)
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
}
