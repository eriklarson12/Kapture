import CoreGraphics
import Testing
@testable import KaptureKit

@Suite("StripRenderer")
struct StripRendererTests {
    let renderer = StripRenderer()

    @Test("renders at the template's pixel size")
    func outputSize() throws {
        let template = BuiltInTemplates.classicStrip
        let image = try renderer.render(frames: TestImage.frames(4), template: template)
        #expect(image.width == Int(template.canvasSize.width))
        #expect(image.height == Int(template.canvasSize.height))
    }

    @Test("scales geometry for a print export")
    func printExport() throws {
        let template = BuiltInTemplates.classicStrip
        let image = try renderer.render(
            frames: TestImage.frames(4),
            template: template,
            scale: template.scale(forDPI: 300)
        )
        #expect(image.width == 600)
        #expect(image.height == 1800)
    }

    @Test("rejects the wrong number of frames")
    func frameCountMismatch() {
        #expect(throws: StripRenderError.frameCountMismatch(expected: 4, actual: 2)) {
            try renderer.render(frames: TestImage.frames(2), template: BuiltInTemplates.classicStrip)
        }
    }

    @Test("rejects an unrenderable template")
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
        #expect(throws: StripRenderError.invalidTemplate) {
            try renderer.render(frames: TestImage.frames(4), template: crushed)
        }
    }

    @Test("aspect-fills a wide photo by overflowing horizontally")
    func aspectFillWide() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let wide = TestImage.solid(width: 200, height: 100)
        let rect = StripRenderer.aspectFillRect(for: wide, in: bounds)
        #expect(rect.height == bounds.height)
        #expect(rect.width > bounds.width)
        #expect(rect.midX == bounds.midX)
    }

    @Test("aspect-fills a tall photo by overflowing vertically")
    func aspectFillTall() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tall = TestImage.solid(width: 100, height: 200)
        let rect = StripRenderer.aspectFillRect(for: tall, in: bounds)
        #expect(rect.width == bounds.width)
        #expect(rect.height > bounds.height)
        #expect(rect.midY == bounds.midY)
    }

    @Test("always covers the bounds it is given")
    func aspectFillCovers() {
        let bounds = CGRect(x: 10, y: 20, width: 144, height: 96)
        for (w, h) in [(640, 480), (480, 640), (1000, 100), (100, 1000), (144, 96)] {
            let rect = StripRenderer.aspectFillRect(for: TestImage.solid(width: w, height: h), in: bounds)
            #expect(rect.width >= bounds.width - 0.001)
            #expect(rect.height >= bounds.height - 0.001)
            #expect(rect.contains(bounds.insetBy(dx: 0.001, dy: 0.001)))
        }
    }

    // MARK: - Background assets

    @Test("a picture larger than the print is shrunk to cover it")
    func downscaleShrinksToCover() {
        let source = TestImage.solid(width: 4000, height: 3000)
        let target = CGSize(width: 600, height: 1800)
        let fitted = StripRenderer.downscaled(source, covering: target)

        // Covers on both axes, which is what aspect-fill needs, and is no
        // larger than it has to be on the binding one.
        #expect(CGFloat(fitted.width) >= target.width)
        #expect(CGFloat(fitted.height) >= target.height)
        #expect(fitted.height == Int(target.height))
        #expect(fitted.width < source.width)
    }

    @Test("a picture smaller than the print is left alone")
    func downscaleNeverEnlarges() {
        let source = TestImage.solid(width: 100, height: 100)
        let fitted = StripRenderer.downscaled(source, covering: CGSize(width: 600, height: 1800))
        #expect(fitted.width == 100)
        #expect(fitted.height == 100)
    }

    @Test("a standalone photo comes out at the size it was asked for")
    func photoSize() throws {
        let photo = try StripRenderer.photo(
            TestImage.asymmetric(), size: CGSize(width: 400, height: 300)
        )
        #expect(photo.width == 400)
        #expect(photo.height == 300)
    }

    /// The distinction that matters for an animation export: a 16:9 shot in a
    /// 4:3 frame must lose its edges, not be squeezed. A centred boundary sits
    /// in the middle either way, so the marked edge is what proves it.
    @Test("a standalone photo is cropped, not squashed")
    func photoCrops() throws {
        let photo = try StripRenderer.photo(
            TestImage.edgeMarked(width: 640, height: 360),
            size: CGSize(width: 400, height: 300)
        )
        let row = photo.height / 2

        // Red would be here if the full width had been squeezed in.
        #expect(TestImage.red(photo, x: 2, y: row) == 0)
        #expect(TestImage.green(photo, x: 2, y: row) == 0)
        // And the black/white boundary is still centred.
        #expect(TestImage.green(photo, x: 190, y: row) == 0)
        #expect(TestImage.green(photo, x: 210, y: row) == 255)
    }

    @Test("a mirrored standalone photo puts the right half on the left")
    func photoMirrors() throws {
        let size = CGSize(width: 400, height: 300)
        let plain = try StripRenderer.photo(TestImage.asymmetric(), size: size)
        let flipped = try StripRenderer.photo(
            TestImage.asymmetric(), size: size, mirrored: true
        )
        #expect(TestImage.red(plain, x: 20, y: 150) == 0)
        #expect(TestImage.red(flipped, x: 20, y: 150) == 255)
        #expect(TestImage.red(flipped, x: 380, y: 150) == 0)
    }

    @Test("a photo with no area is refused rather than drawn")
    func photoRejectsEmptySize() {
        #expect(throws: StripRenderError.contextCreationFailed) {
            try StripRenderer.photo(TestImage.asymmetric(), size: CGSize(width: 0, height: 100))
        }
    }

    /// The property a print sheet stands on: `draw` honours the transform the
    /// caller has already set, and leaves none of its own behind. A save that
    /// went missing would put the second copy somewhere else, or nowhere.
    @Test("the same strip draws twice into one context")
    func drawsTwiceIntoOneContext() throws {
        let template = BuiltInTemplates.classicStrip
        let frames = (0..<4).map { _ in TestImage.asymmetric() }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 288, height: 432, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        // No save or restore here on purpose: the second copy lands correctly
        // only if the first draw left the context as it found it.
        try renderer.draw(frames: frames, template: template, into: context)
        context.translateBy(x: 144, y: 0)
        try renderer.draw(frames: frames, template: template, into: context)

        let sheet = try #require(context.makeImage())
        #expect(TestImage.red(sheet, x: 50, y: 150) == 0)
        #expect(TestImage.red(sheet, x: 100, y: 150) == 255)
        #expect(TestImage.red(sheet, x: 194, y: 150) == 0)
        #expect(TestImage.red(sheet, x: 244, y: 150) == 255)
    }
}
