import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Vision

/// Finds the person in a stored frame and paints a chosen backdrop behind them.
///
/// The only file in the project that imports Vision (ADR-024), the way
/// `FilterRenderer` is the only one that imports CoreImage's filters and
/// `MovieRenderer` the only one that imports AVFoundation's writing half.
/// `StripRenderer` goes on taking finished frames and knowing none of this.
///
/// `mask` and `composite` are deliberately separate. The half that asks a model
/// a question is one function; everything downstream of it takes images and is
/// a function of its input, which is the only half a test can hold still.
enum BackdropRenderer {
    /// The fraction of a mask that must be person before the backdrop is
    /// painted at all.
    ///
    /// Revision 1 answers "nobody here" with an all-zero mask rather than with
    /// no observation, and compositing that replaces the photograph entirely —
    /// somebody sits through a four-shot run and gets a rectangle of colour.
    /// One percent is far below any real subject, so the floor only ever
    /// catches a mask that found nothing.
    static let minimumCoverage = 0.01

    /// Softens the cut in output pixels. Fixed rather than derived from the
    /// frame: a mask edge reads as hard or soft at the size it is printed, and
    /// every frame in this app is printed at the same size.
    static let edgeFeather: CGFloat = 1.5

    /// Coverage is measured on a thumbnail rather than on the full mask. The
    /// question is "did it find anybody", which survives the downsample, and
    /// the full mask is a quarter of a million bytes to walk on every render.
    private static let coverageSampleSize = 64

    // MARK: - Segmentation

    /// The person mask for one frame, as a device-grey image the size Vision
    /// chose, or nil when Vision failed or found nobody worth cutting out.
    ///
    /// The frame handed in MUST be the stored one: true optics, unfiltered. A
    /// mask taken off a filtered frame would be a function of the filter, and a
    /// mask taken off a mirrored frame would cut out the wrong side.
    static func mask(for image: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        // Spelled out rather than left to `defaultRevision`, which moves with
        // the OS. A mask is a function of its input and of the revision that
        // computed it; this is the half of that pair the project controls.
        if VNGeneratePersonSegmentationRequest.supportedRevisions
            .contains(VNGeneratePersonSegmentationRequestRevision1) {
            request.revision = VNGeneratePersonSegmentationRequestRevision1
        }
        // One quality level everywhere. A preview at `.balanced` and an export
        // at `.accurate` is the export saving a strip nobody saw. Balanced is
        // already at the paper's resolution: a 1920x1080 frame gives a 512x384
        // mask, and a photo band on the classic strip at 300 dpi is 534x384.
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // A strip comes out with the room it was shot in rather than not at
            // all. Same rule as a filter that fails.
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

    /// The fraction of `mask` that is person, between 0 and 1.
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

    /// Vision hands back a one-component buffer. It becomes a device-grey image
    /// rather than a `CIImage` over the buffer directly, because
    /// `CIBlendWithMask` reads the mask's luminance and a one-component buffer
    /// wrapped as a `CIImage` arrives as a red channel — a mask that would then
    /// be applied at roughly a third of its strength.
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

    // MARK: - Compositing

    /// `image` kept where `mask` says person, `backdrop` everywhere else.
    ///
    /// Pure CoreImage: same three images in, same bytes out. The mask is scaled
    /// to the photograph rather than the photograph to the mask, so nothing the
    /// camera recorded is thrown away to match a model's output size.
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

    /// Blurred and then clamped back, because a blur reads the pixels outside
    /// the mask as transparent and would eat the edge of a subject standing
    /// against the side of the frame.
    private static func feathered(_ mask: CIImage, in extent: CGRect) -> CIImage {
        guard edgeFeather > 0 else { return mask }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mask.clampedToExtent()
        blur.radius = Float(edgeFeather)
        return (blur.outputImage ?? mask).cropped(to: extent)
    }
}
