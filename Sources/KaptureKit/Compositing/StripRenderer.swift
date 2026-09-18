import CoreGraphics
import Foundation

public enum StripRenderError: Error, Equatable {
    case invalidTemplate
    case frameCountMismatch(expected: Int, actual: Int)
    case contextCreationFailed
}

/// Draws frames into a template. Pure CoreGraphics, no AppKit, no camera, so
/// every layout decision in the app is unit-testable without hardware.
public struct StripRenderer {
    public init() {}

    /// Renders `frames` into `template`. Scale 1 gives point-for-pixel preview
    /// geometry; use `template.scale(forDPI:)` for a print export.
    public func render(frames: [CGImage], template: StripTemplate, scale: CGFloat = 1) throws -> CGImage {
        guard template.isValid else { throw StripRenderError.invalidTemplate }
        guard frames.count == template.frameCount else {
            throw StripRenderError.frameCountMismatch(expected: template.frameCount, actual: frames.count)
        }
        guard scale > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw StripRenderError.contextCreationFailed
        }

        let pixelSize = CGSize(
            width: (template.canvasSize.width * scale).rounded(),
            height: (template.canvasSize.height * scale).rounded()
        )
        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StripRenderError.contextCreationFailed
        }

        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(template.background.cgColor)
        context.fill(CGRect(origin: .zero, size: template.canvasSize))

        for (rect, image) in zip(template.photoRects(), frames) {
            context.saveGState()
            if template.cornerRadius > 0 {
                context.addPath(
                    CGPath(
                        roundedRect: rect,
                        cornerWidth: template.cornerRadius,
                        cornerHeight: template.cornerRadius,
                        transform: nil
                    )
                )
                context.clip()
            } else {
                context.clip(to: rect)
            }
            context.draw(image, in: Self.aspectFillRect(for: image, in: rect))
            context.restoreGState()
        }

        guard let output = context.makeImage() else { throw StripRenderError.contextCreationFailed }
        return output
    }

    /// The rect to draw `image` into so it covers `bounds` with no distortion,
    /// overflowing on whichever axis is long. The caller clips to `bounds`.
    static func aspectFillRect(for image: CGImage, in bounds: CGRect) -> CGRect {
        guard image.height > 0, bounds.height > 0 else { return bounds }
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let boundsAspect = bounds.width / bounds.height

        if imageAspect > boundsAspect {
            let width = bounds.height * imageAspect
            return CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: bounds.height)
        }
        let height = bounds.width / imageAspect
        return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }
}
