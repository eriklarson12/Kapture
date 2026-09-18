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
            let plain = try store.save(frames: frames, templateID: template.id)
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
}
