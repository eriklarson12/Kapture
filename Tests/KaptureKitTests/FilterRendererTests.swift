import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("FilterRenderer")
struct FilterRendererTests {
    /// A mid-warm patch: saturated enough that a desaturating filter is
    /// unmistakable, and not so saturated that a contrast bump clips.
    private func warm() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.7, green: 0.45, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context.makeImage()!
    }

    private func rgb(_ image: CGImage, x: Int = 32, y: Int = 32) -> (UInt8, UInt8, UInt8) {
        let pixels = TestImage.pixels(image)
        let offset = y * image.width * 4 + x * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    @Test("no filter returns the frame untouched, pixel for pixel")
    func noneIsIdentity() {
        let source = warm()
        let output = FilterRenderer.apply(.none, to: source)
        #expect(TestImage.pixels(output) == TestImage.pixels(source))
    }

    @Test("every filter keeps the frame's dimensions")
    func preservesSize() {
        let source = warm()
        for filter in PhotoFilter.allCases {
            let output = FilterRenderer.apply(filter, to: source)
            #expect(output.width == source.width, "\(filter)")
            #expect(output.height == source.height, "\(filter)")
        }
    }

    @Test("black and white leaves no colour behind")
    func monoIsGrey() {
        let (red, green, blue) = rgb(FilterRenderer.apply(.blackAndWhite, to: warm()))
        #expect(abs(Int(red) - Int(green)) <= 1)
        #expect(abs(Int(green) - Int(blue)) <= 1)
    }

    /// Measured against a neutral patch: sepia maps luminance onto a fixed brown
    /// ramp, so an already-warm source could narrow the spread it widens here.
    @Test("sepia tints a neutral frame brown, so red leads blue")
    func sepiaWarms() {
        let source = TestImage.solid(width: 64, height: 64, gray: 0.5)
        let (sourceRed, _, sourceBlue) = rgb(source)
        #expect(sourceRed == sourceBlue)
        let (red, _, blue) = rgb(FilterRenderer.apply(.sepia, to: source))
        #expect(Int(red) - Int(blue) > Int(sourceRed) - Int(sourceBlue))
    }

    @Test("high contrast pushes a light patch lighter")
    func contrastLightens() {
        // 0.7 red is above the 0.5 pivot `CIColorControls` works around, so
        // raising contrast must move it up rather than merely move it.
        let (red, _, _) = rgb(FilterRenderer.apply(.highContrast, to: warm()))
        let (sourceRed, _, _) = rgb(warm())
        #expect(red > sourceRed)
    }

    @Test("grain disturbs a flat patch")
    func grainAddsTexture() {
        let source = warm()
        let output = FilterRenderer.apply(.grain, to: source)
        let pixels = TestImage.pixels(output)
        let reds = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) }
        #expect(Set(reds).count > 1, "a flat patch came back flat")
    }

    /// The guarantee export rests on: a 300 dpi render is *separate* from the
    /// preview, so fresh noise each time would save a strip the user never saw.
    @Test("filtering twice gives byte-identical results")
    func filteringIsDeterministic() {
        let source = warm()
        for filter in PhotoFilter.allCases {
            let first = TestImage.pixels(FilterRenderer.apply(filter, to: source))
            let second = TestImage.pixels(FilterRenderer.apply(filter, to: source))
            #expect(first == second, "\(filter) is not reproducible")
        }
    }
}
