import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("BackdropRenderer")
struct BackdropRendererTests {
    /// A backdrop that is unmistakably not the photograph, so a pixel says
    /// which of the two it came from without any arithmetic.
    private func red(width: Int = 640, height: Int = 480) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("the mask decides which half of the frame survives")
    func compositeFollowsMask() {
        // The photograph is black left, white right; the mask keeps the left.
        let output = BackdropRenderer.composite(
            TestImage.asymmetric(), over: red(), mask: TestImage.mask()
        )

        // Sampled well inside each half, so the feather at the seam is not
        // what is being read.
        #expect(TestImage.red(output, x: 5, y: 240) < 32)
        #expect(TestImage.green(output, x: 5, y: 240) < 32)
        #expect(TestImage.red(output, x: 635, y: 240) > 223)
        #expect(TestImage.green(output, x: 635, y: 240) < 32)
    }

    @Test("compositing twice gives byte-identical results")
    func compositeIsDeterministic() {
        let frame = TestImage.asymmetric()
        let backdrop = red()
        let mask = TestImage.mask()
        let first = BackdropRenderer.composite(frame, over: backdrop, mask: mask)
        let second = BackdropRenderer.composite(frame, over: backdrop, mask: mask)
        #expect(TestImage.pixels(first) == TestImage.pixels(second))
    }

    @Test("the composite keeps the frame's dimensions")
    func preservesSize() {
        let frame = TestImage.solid(width: 200, height: 150)
        let output = BackdropRenderer.composite(
            frame,
            over: red(width: 64, height: 48),
            mask: TestImage.mask(width: 320, height: 240)
        )
        #expect(output.width == 200)
        #expect(output.height == 150)
    }

    @Test("a mask that found nobody leaves the photograph alone")
    func emptyMaskIsRefused() {
        let mask = TestImage.mask(personFraction: 0)
        #expect(BackdropRenderer.coverage(of: mask) < BackdropRenderer.minimumCoverage)
    }

    @Test("a mask covering everything is a person, not a failure")
    func fullMaskIsAccepted() {
        let mask = TestImage.mask(personFraction: 1)
        #expect(BackdropRenderer.coverage(of: mask) > 0.99)
    }

    @Test("coverage counts the person, not the picture")
    func measuresCoverage() {
        #expect(abs(BackdropRenderer.coverage(of: TestImage.mask(personFraction: 0.5)) - 0.5) < 0.05)
        #expect(abs(BackdropRenderer.coverage(of: TestImage.mask(personFraction: 0.25)) - 0.25) < 0.05)
    }

    /// The only test that runs Vision. A flat patch holds no person, so the only
    /// guarantee tested is that the caller still gets a photograph back either way.
    @Test("a frame with no person in it still comes back a photograph")
    func visionOnAFlatPatchIsSafe() {
        let frame = TestImage.solid(width: 320, height: 240)
        guard let mask = BackdropRenderer.mask(for: frame) else {
            return
        }
        let output = BackdropRenderer.composite(frame, over: red(), mask: mask)
        #expect(output.width == 320)
        #expect(output.height == 240)
    }
}
