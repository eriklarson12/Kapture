import CoreGraphics
import Testing
@testable import KaptureKit

@Suite("SheetLayout")
struct SheetLayoutTests {
    private let sheet = SheetLayout()

    @Test("a 2x6 strip tiles a 4x6 sheet exactly twice")
    func classicTilesTwice() {
        let places = sheet.placements(for: BuiltInTemplates.classicStrip)
        #expect(places.count == 2)
        #expect(places[0] == CGRect(x: 0, y: 0, width: 144, height: 432))
        #expect(places[1] == CGRect(x: 144, y: 0, width: 144, height: 432))
    }

    @Test("a three-shot strip is the same stock and tiles the same way")
    func tripleTilesTwice() {
        #expect(sheet.placements(for: BuiltInTemplates.tripleStrip).count == 2)
    }

    @Test("a 4x6 template fills the sheet once")
    func wideFillsOnce() {
        let places = sheet.placements(for: BuiltInTemplates.wideStrip)
        #expect(places.count == 1)
        #expect(places[0] == CGRect(x: 0, y: 0, width: 288, height: 432))
    }

    /// A grid is already the size of the stock, so it prints once and is not
    /// cut. Nothing in `SheetLayout` knows about columns; this is here so that
    /// stays true.
    @Test("a 2x2 grid fills the sheet once, uncut")
    func gridFillsOnce() {
        let places = sheet.placements(for: BuiltInTemplates.gridQuad)
        #expect(places.count == 1)
        #expect(places[0] == CGRect(x: 0, y: 0, width: 288, height: 432))
    }

    /// Scaled rather than cropped. A cropped strip prints with one border
    /// missing and reads as a printer fault rather than as a layout that did
    /// not fit.
    @Test("a template too large for the sheet is scaled down, not cut")
    func oversizeScales() {
        let big = StripTemplate(
            id: "big", name: "Big", frameCount: 4,
            canvasSize: CGSize(width: 576, height: 864),
            outerInset: 8, gutter: 6, footerHeight: 30
        )
        let places = sheet.placements(for: big)
        #expect(places.count == 1)
        #expect(places[0].width == 288)
        #expect(places[0].height == 432)
    }

    @Test("a copy that does not fill the width is centred as a block")
    func centresLeftovers() {
        let narrow = StripTemplate(
            id: "narrow", name: "Narrow", frameCount: 4,
            canvasSize: CGSize(width: 100, height: 432),
            outerInset: 8, gutter: 6, footerHeight: 30
        )
        let places = sheet.placements(for: narrow)
        #expect(places.count == 2)
        // 288 - 200 = 88 of slack, half of it on each side.
        #expect(places[0].minX == 44)
        #expect(places[1].maxX == 244)
    }

    @Test("a shorter strip is centred vertically")
    func centresVertically() {
        let short = StripTemplate(
            id: "short", name: "Short", frameCount: 2,
            canvasSize: CGSize(width: 144, height: 216),
            outerInset: 8, gutter: 6, footerHeight: 30
        )
        let places = sheet.placements(for: short)
        #expect(places[0].minY == 108)
        #expect(places[0].height == 216)
    }
}
