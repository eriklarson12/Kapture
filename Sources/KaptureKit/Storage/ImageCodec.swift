import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case encodeFailed
    case decodeFailed
}

/// The one place images become bytes and back, so every encoder is configured
/// once. PNG rather than HEIC: the round trip is pixel-exact, testable by comparing images directly.
public enum ImageCodec {
    /// Encodes `image` as PNG. `dpi` writes physical-size metadata, so an
    /// exported strip prints at a true 2x6 inches rather than a guess.
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

    /// Encodes `frames` as a GIF that loops forever. Both delay keys are
    /// written on purpose: decoders clamp the plain one, older ones don't know the unclamped one exists.
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
