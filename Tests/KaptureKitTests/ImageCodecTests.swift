import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import KaptureKit

@Suite("ImageCodec")
struct ImageCodecTests {
    @Test("a PNG round trip preserves dimensions and pixels exactly")
    func roundTripIsExact() throws {
        let original = TestImage.asymmetric(width: 120, height: 80)
        let decoded = try ImageCodec.decodePNG(ImageCodec.encodePNG(original))

        #expect(decoded.width == 120)
        #expect(decoded.height == 80)
        #expect(TestImage.pixels(decoded) == TestImage.pixels(original))
    }

    /// A strip is meant to print at a true 2x6 inches. Without this metadata a
    /// printer guesses, and the guess is 72 dpi.
    @Test("an exported PNG carries its resolution")
    func writesDPI() throws {
        let data = try ImageCodec.encodePNG(TestImage.solid(width: 600, height: 1800), dpi: 300)
        #expect(ImageCodec.dpi(of: data) == 300)
    }

    @Test("omitting the dpi writes no resolution claim")
    func omitsDPI() throws {
        let data = try ImageCodec.encodePNG(TestImage.solid(width: 10, height: 10))
        #expect(ImageCodec.dpi(of: data) == nil)
    }

    @Test("rejects bytes that are not an image")
    func rejectsGarbage() {
        #expect(throws: ImageCodecError.decodeFailed) {
            try ImageCodec.decodePNG(Data([0x00, 0x01, 0x02, 0x03]))
        }
    }

    private func gifSource(_ data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    private func gifProperties(_ source: CGImageSource, at index: Int) -> [CFString: Any]? {
        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[
            kCGImagePropertyGIFDictionary
        ] as? [CFString: Any]
    }

    @Test("a GIF carries every frame it was given")
    func gifFrameCount() throws {
        let data = try ImageCodec.encodeGIF(TestImage.frames(4, width: 40, height: 30), delaySeconds: 0.6)
        let source = try #require(gifSource(data))
        #expect(CGImageSourceGetCount(source) == 4)
    }

    /// Both keys: the clamped one is floored by decoders, and old decoders
    /// don't know the unclamped one exists — writing only one misplays the speed.
    @Test("a GIF records its delay in both the clamped and unclamped keys")
    func gifDelay() throws {
        let data = try ImageCodec.encodeGIF(TestImage.frames(2, width: 40, height: 30), delaySeconds: 0.6)
        let source = try #require(gifSource(data))
        let properties = try #require(gifProperties(source, at: 0))

        let unclamped = try #require(properties[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        let clamped = try #require(properties[kCGImagePropertyGIFDelayTime] as? Double)
        #expect(abs(unclamped - 0.6) < 0.001)
        #expect(abs(clamped - 0.6) < 0.001)
    }

    @Test("a GIF loops forever")
    func gifLoops() throws {
        let data = try ImageCodec.encodeGIF(TestImage.frames(2, width: 40, height: 30), delaySeconds: 0.6)
        let source = try #require(gifSource(data))
        let properties = try #require(
            (CGImageSourceCopyProperties(source, nil) as? [CFString: Any])?[
                kCGImagePropertyGIFDictionary
            ] as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyGIFLoopCount] as? Int == 0)
    }

    @Test("a GIF with no frames is refused rather than written empty")
    func gifRejectsEmpty() {
        #expect(throws: ImageCodecError.encodeFailed) {
            try ImageCodec.encodeGIF([], delaySeconds: 0.6)
        }
    }
}
