import CoreGraphics
import CoreImage
import Foundation

public enum QRCodeError: Error, Equatable {
    case generatorUnavailable
    case encodingFailed
}

/// A QR code for a URL, drawn the way a phone camera expects to find one.
///
/// **Black modules on white, with a quiet zone**, never inverted and never
/// over the viewport's black. A light-on-dark code is readable by some phones
/// and not others, and a code with no margin is readable by almost none; both
/// failures look like "the camera did not see it" rather than like a bug. The
/// white card is luminance, not colour, so ADR-004 is untouched.
public enum QRCode {
    /// Four modules is what the specification asks for. Anything less and a
    /// code printed against a dark background stops scanning.
    public static let quietZoneModules = 4

    /// Renders `text` at one integral scale, so every module is the same number
    /// of pixels and no edge is interpolated into grey.
    ///
    /// `minimumSize` is a floor rather than the answer: a code is scaled by a
    /// whole number of pixels per module and the result is at least this wide.
    public static func image(for text: String, minimumSize: CGFloat = 512) throws -> CGImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QRCodeError.generatorUnavailable
        }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        // Medium: a booth's code is on a screen at arm's length, not on a
        // lorry. High correction would make the modules smaller for no gain.
        filter.setValue("M", forKey: "inputCorrectionLevel")

        let context = CIContext()
        guard let output = filter.outputImage,
              let modules = context.createCGImage(output, from: output.extent) else {
            throw QRCodeError.encodingFailed
        }

        let across = modules.width + quietZoneModules * 2
        // Rounded up, because the name says minimum: rounding down returns a
        // code smaller than the space it was asked to fill, and the caller has
        // no way to tell.
        let scale = max(1, Int((minimumSize / CGFloat(across)).rounded(.up)))
        let side = across * scale

        guard let canvas = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw QRCodeError.encodingFailed }

        canvas.setFillColor(gray: 1, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // Nearest-neighbour, or a scaled module gets a soft edge and the
        // decoder has to guess where one ends.
        canvas.interpolationQuality = .none
        canvas.draw(
            modules,
            in: CGRect(
                x: quietZoneModules * scale,
                y: quietZoneModules * scale,
                width: modules.width * scale,
                height: modules.height * scale
            )
        )

        guard let image = canvas.makeImage() else { throw QRCodeError.encodingFailed }
        return image
    }
}
