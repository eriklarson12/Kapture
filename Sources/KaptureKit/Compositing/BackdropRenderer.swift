import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Vision

/// The only file that imports Vision (ADR-024). `mask` and `composite` are
/// separate so the model call stays isolated from pure, testable image math.
enum BackdropRenderer {
    /// Vision answers "nobody here" with an all-zero mask, not a failure, so
    /// a low floor is what keeps that from painting over the whole photograph.
    static let minimumCoverage = 0.01

    /// Fixed in output pixels rather than derived from frame size — every
    /// frame in this app prints at the same size.
    static let edgeFeather: CGFloat = 1.5

    /// Measured on a downsampled thumbnail — "did it find anybody" survives
    /// the downsample and the full mask is expensive to walk every render.
    private static let coverageSampleSize = 64

    /// `image` must be the stored, true-optics frame: a mask off a filtered
    /// or mirrored frame would misread the filter, or cut the wrong side.
    static func mask(for image: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        // Pinned rather than left to `defaultRevision`, which moves with the
        // OS — a mask must be a function of a revision the project controls.
        if VNGeneratePersonSegmentationRequest.supportedRevisions
            .contains(VNGeneratePersonSegmentationRequestRevision1) {
            request.revision = VNGeneratePersonSegmentationRequestRevision1
        }
        // One quality level everywhere — a preview at `.balanced` and an
        // export at `.accurate` would mean the export saves a strip nobody saw.
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // A strip comes out with the room it was shot in rather than not
            // at all — same rule as a filter that fails.
            return nil
        }

        guard let observation = request.results?.first as? VNPixelBufferObservation,
              let grey = greyImage(from: observation.pixelBuffer),
              coverage(of: grey) >= minimumCoverage
        else {
            return nil
        }
        return grey
    }

    static func coverage(of mask: CGImage) -> Double {
        let longest = max(mask.width, mask.height)
        let divisor = max(1, Int((Double(longest) / Double(coverageSampleSize)).rounded(.up)))
        let width = max(1, mask.width / divisor)
        let height = max(1, mask.height / divisor)

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }

        let person = pixels.reduce(into: 0) { total, value in
            if value > 127 { total += 1 }
        }
        return Double(person) / Double(width * height)
    }

    /// A one-component buffer wrapped directly as `CIImage` reads as the red
    /// channel to `CIBlendWithMask`, applying the mask at roughly 1/3 strength.
    private static func greyImage(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                  data: base,
                  width: CVPixelBufferGetWidth(buffer),
                  height: CVPixelBufferGetHeight(buffer),
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else {
            return nil
        }
        return context.makeImage()
    }

    /// The mask is scaled to the photograph, not the photograph to the mask,
    /// so nothing the camera recorded is thrown away to match the model's size.
    static func composite(_ image: CGImage, over backdrop: CGImage, mask: CGImage) -> CGImage {
        let source = CIImage(cgImage: image)
        let extent = source.extent

        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = fitted(CIImage(cgImage: backdrop), to: extent)
        blend.maskImage = feathered(fitted(CIImage(cgImage: mask), to: extent), in: extent)

        guard let output = blend.outputImage,
              let colorSpace = FilterRenderer.outputColorSpace,
              let result = FilterRenderer.context.createCGImage(
                  output, from: extent, format: .RGBA8, colorSpace: colorSpace
              )
        else {
            // A backdrop that cannot be built must not lose the photograph.
            return image
        }
        return result
    }

    private static func fitted(_ image: CIImage, to extent: CGRect) -> CIImage {
        guard image.extent.width > 0, image.extent.height > 0 else { return image }
        let transform = CGAffineTransform(
            scaleX: extent.width / image.extent.width,
            y: extent.height / image.extent.height
        )
        return image.transformed(by: transform)
    }

    /// Blurred then clamped back — an unclamped blur reads pixels outside the
    /// mask as transparent, eating the edge of a subject at the frame's side.
    private static func feathered(_ mask: CIImage, in extent: CGRect) -> CIImage {
        guard edgeFeather > 0 else { return mask }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mask.clampedToExtent()
        blur.radius = Float(edgeFeather)
        return (blur.outputImage ?? mask).cropped(to: extent)
    }
}
