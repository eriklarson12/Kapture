import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("PDFRenderer")
struct PDFRendererTests {
    private func strip(
        _ template: StripTemplate = BuiltInTemplates.classicStrip,
        caption: String? = nil
    ) -> ResolvedStrip {
        ResolvedStrip(
            template: template,
            frames: (0..<template.frameCount).map { _ in TestImage.asymmetric() },
            caption: caption
        )
    }

    private func firstPage(_ data: Data) throws -> CGPDFPage {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        return try #require(document.page(at: 1))
    }

    /// One entry of the page dictionary's `/Resources`, which is where
    /// CoreGraphics records what the page needed: a `/Font` for real text, an
    /// `/XObject` for each image.
    private func resources(_ page: CGPDFPage, _ key: String) -> CGPDFDictionaryRef? {
        guard let pageDictionary = page.dictionary else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources),
              let resources else { return nil }
        var found: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, key, &found) else { return nil }
        return found
    }

    private func raster(_ data: Data, scale: CGFloat) throws -> CGImage {
        let page = try firstPage(data)
        let box = page.getBoxRect(.mediaBox)
        let width = Int((box.width * scale).rounded())
        let height = Int((box.height * scale).rounded())
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return try #require(context.makeImage())
    }

    /// The media box is in points, not pixels. A box of 600x1800 is a page
    /// eight inches by twenty-five, and nothing short of a ruler says so.
    @Test("the page measures a true 2x6 inches")
    func mediaBoxIsInPoints() throws {
        let box = try firstPage(PDFRenderer.page(strip())).getBoxRect(.mediaBox)
        #expect(box.width == 144)
        #expect(box.height == 432)
    }

    /// The whole claim of a vector page in one check: a caption drawn as glyphs
    /// puts a font in the page's resources; drawn as pixels it does not.
    @Test("a caption is embedded as text, not as pixels")
    func captionIsText() throws {
        let captioned = try firstPage(PDFRenderer.page(strip(caption: "Hello")))
        let bare = try firstPage(PDFRenderer.page(strip()))
        #expect(resources(captioned, "Font") != nil)
        #expect(resources(bare, "Font") == nil)
    }

    /// A PDF wrapping a 72 dpi raster would pass every other check and fail this
    /// one: the last two samples straddle a photo edge that an upscaled raster smears.
    @Test("the page draws the same strip the renderer draws")
    func matchesTheBitmapRender() throws {
        let template = BuiltInTemplates.classicStrip
        let subject = strip(template, caption: "Hello")
        let scale = template.scale(forDPI: 300)

        let direct = try subject.render(scale: scale)
        let fromPDF = try raster(PDFRenderer.page(subject), scale: scale)
        #expect(direct.width == fromPDF.width)
        #expect(direct.height == fromPDF.height)

        // A paper corner, the middle of each half of a photo, the footer band,
        // and then four pixels each side of the edge at x 300.
        for (x, y) in [(4, 4), (200, 900), (400, 900), (300, 1770), (296, 600), (304, 600)] {
            let a = Int(TestImage.red(direct, x: x, y: y))
            let b = Int(TestImage.red(fromPDF, x: x, y: y))
            #expect(abs(a - b) <= 8, "at \(x),\(y): \(a) vs \(b)")
        }
        #expect(TestImage.red(fromPDF, x: 296, y: 600) < 8)
        #expect(TestImage.red(fromPDF, x: 304, y: 600) > 247)
    }

    @Test("a sheet is 4x6 and carries the strip twice")
    func sheetTilesTwice() throws {
        let data = try PDFRenderer.sheet(strip(), layout: SheetLayout())
        let box = try firstPage(data).getBoxRect(.mediaBox)
        #expect(box.width == 288)
        #expect(box.height == 432)

        // A transform left behind by the first copy would move, flip or blank
        // the second; y 300 lands inside the second photo of each copy.
        let sheet = try raster(data, scale: 2)
        for offset in [0, 288] {
            #expect(TestImage.red(sheet, x: offset + 100, y: 300) == 0)
            #expect(TestImage.red(sheet, x: offset + 200, y: 300) == 255)
        }
    }

    @Test("a sheet with nowhere to put the strip is refused, not left blank")
    func rejectsEmptySheet() {
        #expect(throws: PDFRenderError.emptySheet) {
            try PDFRenderer.sheet(strip(), layout: SheetLayout(pageSize: .zero))
        }
    }
}
