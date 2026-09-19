import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("RecipeRenderer")
struct RecipeRendererTests {
    private func withStore(_ body: (StripStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "KaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(StripStore(root: root))
    }

    private func asymmetricFrames(_ count: Int) -> [CaptureFrame] {
        (0..<count).map { CaptureFrame(index: $0, image: TestImage.asymmetric()) }
    }

    /// Sampled at the canvas's vertical centre, which for the classic strip
    /// lands inside a photo. The test image is uniform top to bottom, so the
    /// row does not matter beyond that.
    private func sample(_ strip: CGImage, x: Int) -> UInt8 {
        TestImage.red(strip, x: x, y: strip.height / 2)
    }

    @Test("renders a stored recipe at preview size")
    func rendersAtPreviewSize() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let recipe = try store.save(frames: asymmetricFrames(4), templateID: template.id)
            let strip = try RecipeRenderer(store: store).render(recipe)

            #expect(strip.width == Int(template.canvasSize.width))
            #expect(strip.height == Int(template.canvasSize.height))
        }
    }

    @Test("renders at 300 dpi to the template's print size")
    func rendersAtPrintSize() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let recipe = try store.save(frames: asymmetricFrames(4), templateID: template.id)
            let strip = try RecipeRenderer(store: store)
                .render(recipe, scale: template.scale(forDPI: 300))

            #expect(CGSize(width: strip.width, height: strip.height) == template.pixelSize(atDPI: 300))
        }
    }

    @Test("mirrorOutput flips each photo about its own centre")
    func mirrors() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let frames = asymmetricFrames(4)
            // Both spelled out. The flag is what this test is about, so it must
            // not read the default, which is where the default's own test lives.
            let plain = try store.save(
                frames: frames, templateID: template.id, mirrorOutput: false
            )
            let mirrored = try store.save(
                frames: frames, templateID: template.id, mirrorOutput: true
            )

            let renderer = RecipeRenderer(store: store)
            let left = 20
            let right = Int(template.canvasSize.width) - 20

            let plainStrip = try renderer.render(plain)
            #expect(sample(plainStrip, x: left) < 32)
            #expect(sample(plainStrip, x: right) > 223)

            let mirroredStrip = try renderer.render(mirrored)
            #expect(sample(mirroredStrip, x: left) > 223)
            #expect(sample(mirroredStrip, x: right) < 32)
        }
    }

    @Test("a recorded filter reaches the rendered strip")
    func appliesStoredFilter() throws {
        try withStore { store in
            // Neutral frames, so any colour in the output came from the filter
            // and not from the photograph.
            let frames = (0..<4).map {
                CaptureFrame(index: $0, image: TestImage.solid(width: 64, height: 64, gray: 0.5))
            }
            var recipe = try store.save(
                frames: frames, templateID: BuiltInTemplates.classicStrip.id
            )
            let renderer = RecipeRenderer(store: store)

            let plain = try renderer.render(recipe)
            recipe.filter = .sepia
            try store.update(recipe)
            let toned = try renderer.render(try store.load(id: recipe.id))

            // Inside the first photo band, which `photoRects()` puts at the top.
            let point = CGPoint(x: 72, y: 60)
            #expect(channels(plain, point).red == channels(plain, point).blue)
            #expect(channels(toned, point).red > channels(toned, point).blue)
        }
    }

    private func channels(_ strip: CGImage, _ point: CGPoint) -> (red: Int, blue: Int) {
        let pixels = TestImage.pixels(strip)
        let offset = Int(point.y) * strip.width * 4 + Int(point.x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 2]))
    }

    @Test("an unknown template id names itself")
    func unknownTemplate() throws {
        try withStore { store in
            let recipe = try store.save(frames: asymmetricFrames(4), templateID: "not-a-template")
            #expect(throws: RecipeRenderError.unknownTemplate("not-a-template")) {
                try RecipeRenderer(store: store).render(recipe)
            }
        }
    }

    @Test("a frame count that does not fit the template is rejected")
    func frameCountMismatch() throws {
        try withStore { store in
            // Three frames against the four-frame classic strip.
            let recipe = try store.save(
                frames: asymmetricFrames(3), templateID: BuiltInTemplates.classicStrip.id
            )
            #expect(throws: StripRenderError.frameCountMismatch(expected: 4, actual: 3)) {
                try RecipeRenderer(store: store).render(recipe)
            }
        }
    }

    @Test("a style override changes the paper the strip is printed on")
    func styleOverridesBackground() throws {
        try withStore { store in
            var recipe = try store.save(
                frames: asymmetricFrames(4), templateID: BuiltInTemplates.classicStrip.id
            )
            let plain = try RecipeRenderer(store: store).render(recipe)
            // The very corner is border, never photo, so it is the paper.
            #expect(TestImage.red(plain, x: 0, y: 0) == 255)

            recipe.style = StripStyle(background: .solid(RGBA(red: 0, green: 0, blue: 0)))
            try store.update(recipe)
            let dark = try RecipeRenderer(store: store).render(try store.load(id: recipe.id))
            #expect(TestImage.red(dark, x: 0, y: 0) == 0)
        }
    }

    @Test("a border override moves where the photos start")
    func styleOverridesInset() throws {
        try withStore { store in
            // Unmirrored on purpose: the border is located by finding the test
            // image's black left edge, so which way round the photo sits is
            // part of the measurement and must not come from a default.
            var recipe = try store.save(
                frames: asymmetricFrames(4),
                templateID: BuiltInTemplates.classicStrip.id,
                mirrorOutput: false
            )
            recipe.style = StripStyle(outerInset: 24)
            try store.update(recipe)

            let strip = try RecipeRenderer(store: store).render(recipe)
            let template = BuiltInTemplates.classicStrip.applying(recipe.style)
            let expectedWidth: CGFloat = 96
            #expect(template.photoWidth == expectedWidth)

            // Canvas size is unchanged; only the photos move inward.
            #expect(strip.width == Int(BuiltInTemplates.classicStrip.canvasSize.width))
            #expect(TestImage.red(strip, x: 20, y: strip.height / 2) == 255)
            #expect(TestImage.red(strip, x: 30, y: strip.height / 2) != 255)
        }
    }

    @Test("a stored caption reaches the rendered strip")
    func rendersStoredCaption() throws {
        try withStore { store in
            var recipe = try store.save(
                frames: asymmetricFrames(4), templateID: BuiltInTemplates.classicStrip.id
            )
            let bare = try RecipeRenderer(store: store).render(recipe)

            recipe.caption = "Kapture"
            try store.update(recipe)
            let captioned = try RecipeRenderer(store: store).render(recipe)

            #expect(TestImage.pixels(bare) != TestImage.pixels(captioned))
        }
    }

    // MARK: - Animation frames

    /// The classic strip's photo aspect is 1.39 against a 4:3 test frame, so
    /// aspect-fill overflows vertically and the full source width survives.
    /// Every sample below at a small x therefore reads the source's left edge.
    private func animationFrames(
        _ store: StripStore, _ recipe: StripRecipe
    ) throws -> [CGImage] {
        try RecipeRenderer(store: store).renderFrames(recipe, height: 400)
    }

    @Test("renderFrames gives one image per shot, at the template's photo aspect")
    func renderFramesShape() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let recipe = try store.save(frames: asymmetricFrames(4), templateID: template.id)
            let frames = try animationFrames(store, recipe)

            #expect(frames.count == 4)
            for frame in frames {
                let aspect = CGFloat(frame.width) / CGFloat(frame.height)
                #expect(abs(aspect - template.photoAspect) < 0.01)
                // H.264 will not take an odd dimension, and the GIF has no
                // reason to be sized differently from the movie.
                #expect(frame.width.isMultiple(of: 2))
                #expect(frame.height.isMultiple(of: 2))
            }
        }
    }

    @Test("the recipe's filter reaches the animation frames")
    func renderFramesFilters() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let coloured = (0..<4).map {
                CaptureFrame(index: $0, image: TestImage.edgeMarked(width: 640, height: 480))
            }
            let plain = try store.save(
                frames: coloured, templateID: template.id, mirrorOutput: false
            )
            var greyed = plain
            greyed.filter = .blackAndWhite

            // Asserted first, so a sample point that missed the red stripe
            // could not make the filter look like it worked.
            let colour = try animationFrames(store, plain)[0]
            #expect(TestImage.red(colour, x: 2, y: colour.height / 2) > 200)
            #expect(TestImage.green(colour, x: 2, y: colour.height / 2) < 50)

            let mono = try animationFrames(store, greyed)[0]
            let row = mono.height / 2
            #expect(TestImage.red(mono, x: 2, y: row) == TestImage.green(mono, x: 2, y: row))
        }
    }

    @Test("mirrorOutput flips the animation frames, like it flips the paper")
    func renderFramesMirror() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let frames = asymmetricFrames(4)
            let plain = try store.save(
                frames: frames, templateID: template.id, mirrorOutput: false
            )
            let mirrored = try store.save(
                frames: frames, templateID: template.id, mirrorOutput: true
            )

            let left = try animationFrames(store, plain)[0]
            let flipped = try animationFrames(store, mirrored)[0]
            #expect(TestImage.red(left, x: 5, y: left.height / 2) == 0)
            #expect(TestImage.red(flipped, x: 5, y: flipped.height / 2) == 255)
        }
    }

    /// The bug this is most likely to have: reading `photoAspect` off the
    /// template rather than off the template with the strip's own overrides
    /// applied, so a GIF is framed differently from the paper it came from.
    @Test("a style override changes the animation crop too")
    func renderFramesFollowsStyle() throws {
        try withStore { store in
            let template = BuiltInTemplates.classicStrip
            let recipe = try store.save(frames: asymmetricFrames(4), templateID: template.id)
            var styled = recipe
            styled.style = StripStyle(outerInset: 20)

            let plain = try animationFrames(store, recipe)[0]
            let wider = try animationFrames(store, styled)[0]
            #expect(plain.height == wider.height)
            #expect(plain.width != wider.width)
        }
    }
}
