import CoreGraphics
import Foundation
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
}
