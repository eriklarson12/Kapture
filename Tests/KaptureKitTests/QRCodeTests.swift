import CoreImage
import Foundation
import Testing
@testable import KaptureKit

@Suite("QRCode")
struct QRCodeTests {
    /// Reads a generated code the way a phone would. If this cannot, nothing
    /// else about the image matters.
    private func decoded(_ image: CGImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature]
        return features?.first?.messageString
    }

    @Test("a generated code reads back as exactly the URL it was given")
    func roundTripsAURL() throws {
        let url = "http://192.168.1.24:52341/s/abcdefgh12345678"
        let image = try QRCode.image(for: url)

        #expect(decoded(image) == url)
    }

    /// An ephemeral port and a sixteen-character token make a longer string
    /// than a QR code's smallest version can hold.
    @Test("a long URL still reads back")
    func roundTripsALongURL() throws {
        let url = "http://192.168.100.200:65535/s/\(ShareToken.mint())/strip.png?cachebust=00000000"
        let image = try QRCode.image(for: url)

        #expect(decoded(image) == url)
    }

    @Test("the code is square, and at least the size asked for")
    func squareAndBigEnough() throws {
        let image = try QRCode.image(for: "http://10.0.0.2:8080/s/abcdefgh12345678", minimumSize: 320)

        #expect(image.width == image.height)
        #expect(image.width >= 320)
    }

    /// The quiet zone is the difference between a code a camera finds and one
    /// it never sees. Its corners are white on every side.
    @Test("the code is surrounded by white")
    func hasAQuietZone() throws {
        let image = try QRCode.image(for: "http://10.0.0.2:8080/s/abcdefgh12345678")
        let data = try #require(image.dataProvider?.data as Data?)
        // A row is padded to an alignment, so the last *pixel* of a row is at
        // `width - 1` and the bytes after it are not pixels at all.
        let row = image.bytesPerRow

        // One pixel in from each corner, in a grey bitmap: white is 255.
        #expect(data[1] == 255)
        #expect(data[image.width - 2] == 255)
        #expect(data[row * (image.height - 1) + 1] == 255)
        #expect(data[row * (image.height - 1) + image.width - 2] == 255)
    }

    /// The same input gives the same image, which is what lets the QR be
    /// rebuilt on every render rather than cached and invalidated.
    @Test("the same URL twice gives identical bytes")
    func deterministic() throws {
        let url = "http://192.168.1.24:52341/s/abcdefgh12345678"
        let first = try ImageCodec.encodePNG(QRCode.image(for: url))
        let second = try ImageCodec.encodePNG(QRCode.image(for: url))

        #expect(first == second)
    }
}
