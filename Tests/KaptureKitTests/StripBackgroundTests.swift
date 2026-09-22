import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("StripBackground")
struct StripBackgroundTests {
    private let cases: [StripBackground] = [
        .solid(RGBA(red: 0.2, green: 0.4, blue: 0.6)),
        .linearGradient(from: .paper, to: .ink, angle: 90),
        .image(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!),
    ]

    @Test("every case round-trips through the blessed coder")
    func roundTrip() throws {
        let encoder = RecipeCoding.encoder()
        let decoder = RecipeCoding.decoder()
        for background in cases {
            let data = try encoder.encode(background)
            #expect(try decoder.decode(StripBackground.self, from: data) == background)
        }
    }

    /// The migration. Every template and every styled strip written before this
    /// type existed holds a bare `RGBA` here, and has to keep opening.
    @Test("a template written before backgrounds were a type still decodes")
    func decodesLegacyTemplate() throws {
        let json = """
        {
          "id": "classic-strip",
          "name": "Classic Strip",
          "frameCount": 4,
          "canvasSize": [144, 432],
          "outerInset": 8,
          "gutter": 6,
          "footerHeight": 30,
          "cornerRadius": 0,
          "background": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
          "foreground": {"red": 0.07, "green": 0.07, "blue": 0.07, "alpha": 1},
          "captionFontSize": 9,
          "captionAlignment": "center"
        }
        """
        let template = try RecipeCoding.decoder().decode(
            StripTemplate.self, from: Data(json.utf8)
        )
        #expect(template.background == .solid(.paper))
    }

    @Test("a strip styled before backgrounds were a type still decodes")
    func decodesLegacyStyle() throws {
        let json = """
        {
          "background": {"red": 0, "green": 0, "blue": 0, "alpha": 1},
          "outerInset": 12
        }
        """
        let style = try RecipeCoding.decoder().decode(StripStyle.self, from: Data(json.utf8))
        #expect(style.background == .solid(RGBA(red: 0, green: 0, blue: 0)))
        #expect(style.outerInset == 12)
    }

    /// A strip re-rendered a year from now has to come out the way it does
    /// today, so the angle convention is pinned rather than left to read off
    /// whatever the renderer happens to do.
    @Test("zero degrees runs left to right")
    func gradientAngleConvention() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 200)
        let (start, end) = StripRenderer.gradientEnds(angle: 0, in: bounds)
        #expect(start.x < end.x)
        #expect(start.y == end.y)

        let (up, down) = StripRenderer.gradientEnds(angle: 90, in: bounds)
        #expect(up.y < down.y)
        #expect(abs(up.x - down.x) < 0.001)
    }

    @Test("both ends of a gradient sit on the canvas edge")
    func gradientSpansTheCanvas() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 200)
        let (start, end) = StripRenderer.gradientEnds(angle: 0, in: bounds)
        #expect(start.x == bounds.minX)
        #expect(end.x == bounds.maxX)
    }

    @Test("a gradient background varies along its axis and not across it")
    func rendersGradient() throws {
        let template = StripTemplate(
            id: "gradient", name: "Gradient", frameCount: 1,
            canvasSize: CGSize(width: 100, height: 100),
            outerInset: 30, gutter: 0, footerHeight: 0,
            background: .linearGradient(
                from: RGBA(red: 0, green: 0, blue: 0),
                to: RGBA(red: 1, green: 1, blue: 1),
                angle: 0
            )
        )
        let strip = try StripRenderer().render(
            frames: [TestImage.solid(width: 20, height: 20)], template: template
        )

        // Sampled in the border, above the photo, so only the background is
        // being read.
        let row = 4
        #expect(TestImage.red(strip, x: 4, y: row) < TestImage.red(strip, x: 95, y: row))
        // Across the axis the gradient is flat, which is what makes it linear.
        // Within a step: CoreGraphics dithers a gradient, so two rows of what
        // is mathematically one value land a count apart.
        let across = abs(
            Int(TestImage.red(strip, x: 4, y: row)) - Int(TestImage.red(strip, x: 4, y: row + 8))
        )
        #expect(across <= 2)
    }

    @Test("an image background covers the whole canvas")
    func rendersImageBackground() throws {
        let template = StripTemplate(
            id: "picture", name: "Picture", frameCount: 1,
            canvasSize: CGSize(width: 100, height: 100),
            outerInset: 30, gutter: 0, footerHeight: 0,
            background: .image(id: UUID())
        )
        let strip = try StripRenderer().render(
            frames: [TestImage.solid(width: 20, height: 20, gray: 0.2)],
            template: template,
            backgroundImage: TestImage.solid(width: 8, height: 8, gray: 1)
        )

        // Every corner, because aspect-fill on a square image into a square
        // canvas must leave nothing uncovered.
        for (x, y) in [(0, 0), (99, 0), (0, 99), (99, 99)] {
            #expect(TestImage.red(strip, x: x, y: y) == 255, "corner \(x),\(y)")
        }
    }

    @Test("a backdrop is painted by the same fill the paper is")
    func paintsBackdrop() throws {
        let size = CGSize(width: 100, height: 100)
        let raster = try StripRenderer.backdrop(
            .linearGradient(
                from: RGBA(red: 0, green: 0, blue: 0),
                to: RGBA(red: 1, green: 1, blue: 1),
                angle: 0
            ),
            size: size,
            image: nil
        )

        #expect(raster.width == 100)
        #expect(raster.height == 100)
        #expect(TestImage.red(raster, x: 4, y: 50) < TestImage.red(raster, x: 95, y: 50))
        // Flat across the axis, within the dither the paper's gradient allows.
        let across = abs(
            Int(TestImage.red(raster, x: 4, y: 20)) - Int(TestImage.red(raster, x: 4, y: 80))
        )
        #expect(across <= 2)
    }

    @Test("a backdrop picture covers the whole frame")
    func paintsBackdropPicture() throws {
        let raster = try StripRenderer.backdrop(
            .image(id: UUID()),
            size: CGSize(width: 64, height: 48),
            image: TestImage.solid(width: 8, height: 8, gray: 1)
        )
        for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47)] {
            #expect(TestImage.red(raster, x: x, y: y) == 255, "corner \(x),\(y)")
        }
    }

    /// Consistent with a missing frame, which already makes a strip refuse to
    /// render rather than render something quietly wrong.
    @Test("an image background with no image names the asset it wanted")
    func missingBackgroundImageThrows() {
        let assetID = UUID()
        let template = StripTemplate(
            id: "picture", name: "Picture", frameCount: 1,
            canvasSize: CGSize(width: 100, height: 100),
            outerInset: 30, gutter: 0, footerHeight: 0,
            background: .image(id: assetID)
        )
        #expect(throws: StripRenderError.missingBackgroundImage(assetID)) {
            try StripRenderer().render(
                frames: [TestImage.solid(width: 20, height: 20)], template: template
            )
        }
    }
}
