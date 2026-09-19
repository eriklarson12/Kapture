import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case encodeFailed
    case decodeFailed
}

/// The one place images become bytes and back. The frame store, the strip
/// export and the animated GIF export all go through here, so every encoder is
/// configured once.
///
/// PNG rather than HEIC, deliberately: the round trip is pixel-exact, which is
/// what makes the frame store testable by comparing images rather than by
/// trusting the encoder. HEIC would cut a strip's roughly 8 MB of frames by
/// about tenfold and is a change behind this API alone, if a long party ever
/// makes that matter.
public enum ImageCodec {
    /// Encodes `image` as PNG. `dpi` writes physical-size metadata, which is
    /// what makes an exported strip print at a true 2x6 inches rather than at
    /// whatever size the printer guesses.
    public static func encodePNG(_ image: CGImage, dpi: CGFloat? = nil) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ImageCodecError.encodeFailed
        }

        var properties: [CFString: Any] = [:]
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(
            destination, image, properties.isEmpty ? nil : properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodeFailed }
        return buffer as Data
    }

    public static func decodePNG(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageCodecError.decodeFailed
        }
        return image
    }

    /// Encodes `frames` as a GIF that loops forever, holding each frame for
    /// `delaySeconds`.
    ///
    /// Both delay keys are written on purpose. Decoders clamp
    /// `kCGImagePropertyGIFDelayTime` to a floor — historically 0.1s, in some
    /// browsers higher — and `kCGImagePropertyGIFUnclampedDelayTime` is the one
    /// that carries the real number, but older readers do not know it exists.
    /// Writing one of the two gets timing that is wrong somewhere.
    public static func encodeGIF(_ frames: [CGImage], delaySeconds: Double) throws -> Data {
        guard !frames.isEmpty else { throw ImageCodecError.encodeFailed }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.gif.identifier as CFString, frames.count, nil
        ) else {
            throw ImageCodecError.encodeFailed
        }

        // Loop count 0 is forever, which is the one thing a booth GIF must do.
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: delaySeconds,
                kCGImagePropertyGIFDelayTime: delaySeconds
            ]
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodeFailed }
        return buffer as Data
    }

    /// The resolution recorded in `data`, or nil if it carries none. Exists so
    /// the export test can assert what a printer will read.
    public static func dpi(of data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyDPIWidth] as? CGFloat else {
            return nil
        }
        return width
    }
}
