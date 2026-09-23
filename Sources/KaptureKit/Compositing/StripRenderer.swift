import CoreGraphics
import Foundation

public enum StripRenderError: Error, Equatable {
    case invalidTemplate
    case frameCountMismatch(expected: Int, actual: Int)
    case contextCreationFailed
    case missingBackgroundImage(UUID)
}

/// Draws frames into a template. Pure CoreGraphics, no AppKit, no camera, so
/// every layout decision in the app is unit-testable without hardware.
public struct StripRenderer {
    public init() {}

    /// Renders `frames` into `template`. Scale 1 gives point-for-pixel preview
    /// geometry; use `template.scale(forDPI:)` for a print export.
    public func render(
        frames: [CGImage],
        template: StripTemplate,
        backgroundImage: CGImage? = nil,
        scale: CGFloat = 1,
        mirrored: Bool = false,
        caption: String? = nil
    ) throws -> CGImage {
        try validate(frames: frames, template: template)
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

        context.scaleBy(x: scale, y: scale)
        try draw(
            frames: frames,
            template: template,
            backgroundImage: backgroundImage,
            mirrored: mirrored,
            caption: caption,
            into: context
        )

        guard let output = context.makeImage() else { throw StripRenderError.contextCreationFailed }
        return output
    }

    /// `mirrored` flips each photo about its own centre, not the canvas, so
    /// the border and footer stay upright; the caption is drawn once, unaffected.
    public func draw(
        frames: [CGImage],
        template: StripTemplate,
        backgroundImage: CGImage? = nil,
        mirrored: Bool = false,
        caption: String? = nil,
        into context: CGContext
    ) throws {
        try validate(frames: frames, template: template)

        context.saveGState()
        defer { context.restoreGState() }

        context.interpolationQuality = .high
        try Self.paint(
            template.background,
            in: CGRect(origin: .zero, size: template.canvasSize),
            image: backgroundImage,
            context: context
        )

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
            if mirrored {
                context.translateBy(x: rect.midX, y: 0)
                context.scaleBy(x: -1, y: 1)
                context.translateBy(x: -rect.midX, y: 0)
            }
            context.draw(image, in: Self.aspectFillRect(for: image, in: rect))
            context.restoreGState()
        }

        if let caption {
            CaptionRenderer.draw(
                caption,
                in: template.footerRect(),
                template: template,
                context: context
            )
        }
    }

    /// The two checks every drawing path shares, in one order, so a PDF caller
    /// and a bitmap caller fail the same way on the same input.
    private func validate(frames: [CGImage], template: StripTemplate) throws {
        guard template.isValid else { throw StripRenderError.invalidTemplate }
        guard frames.count == template.frameCount else {
            throw StripRenderError.frameCountMismatch(
                expected: template.frameCount, actual: frames.count
            )
        }
    }

    /// Static and shared, not private to `draw`, so a backdrop painted behind
    /// a person and the paper's own background never disagree about an angle.
    static func paint(
        _ background: StripBackground, in bounds: CGRect,
        image: CGImage?, context: CGContext
    ) throws {
        switch background {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(bounds)

        case .linearGradient(let from, let to, let angle):
            // Filled first, so a gradient that cannot be built still leaves
            // paper rather than a transparent strip.
            context.setFillColor(from.cgColor)
            context.fill(bounds)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(
                      colorsSpace: colorSpace,
                      colors: [from.cgColor, to.cgColor] as CFArray,
                      locations: [0, 1]
                  )
            else { return }
            let (start, end) = Self.gradientEnds(angle: angle, in: bounds)
            context.saveGState()
            context.clip(to: bounds)
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
            context.restoreGState()

        case .image(let id):
            guard let image else { throw StripRenderError.missingBackgroundImage(id) }
            context.saveGState()
            context.clip(to: bounds)
            context.draw(image, in: Self.aspectFillRect(for: image, in: bounds))
            context.restoreGState()
        }
    }

    /// `angle` is degrees counter-clockwise from left-to-right. Both ends
    /// land on the rect's boundary so the full colour range is used at any angle.
    static func gradientEnds(angle: CGFloat, in bounds: CGRect) -> (CGPoint, CGPoint) {
        let radians = angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: sin(radians))
        // Projecting the half-diagonal onto the direction puts both ends on
        // the boundary — a 45° gradient across a tall strip must reach further.
        let reach = abs(direction.dx) * bounds.width / 2 + abs(direction.dy) * bounds.height / 2
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        return (
            CGPoint(x: centre.x - direction.dx * reach, y: centre.y - direction.dy * reach),
            CGPoint(x: centre.x + direction.dx * reach, y: centre.y + direction.dy * reach)
        )
    }

    /// Lives here, not in `BackdropRenderer`, so one painter is shared — a
    /// gradient behind a subject and behind the photos read the same angle.
    public static func backdrop(
        _ background: StripBackground, size pixelSize: CGSize, image: CGImage?
    ) throws -> CGImage {
        guard pixelSize.width >= 1, pixelSize.height >= 1,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(pixelSize.width),
                  height: Int(pixelSize.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw StripRenderError.contextCreationFailed
        }
        context.interpolationQuality = .high
        try paint(
            background,
            in: CGRect(origin: .zero, size: pixelSize),
            image: image,
            context: context
        )
        guard let output = context.makeImage() else {
            throw StripRenderError.contextCreationFailed
        }
        return output
    }

    /// Never enlarges — a small picture looks soft, but the file never
    /// grows. A phone photo is far more detail than the canvas can print.
    public static func downscaled(_ image: CGImage, covering pixelSize: CGSize) -> CGImage {
        guard image.width > 0, image.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else { return image }
        let factor = max(
            pixelSize.width / CGFloat(image.width),
            pixelSize.height / CGFloat(image.height)
        )
        guard factor < 1 else { return image }

        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Shared with the animation exports, so a frame in a GIF crops exactly
    /// the way the same frame crops on the paper.
    public static func photo(
        _ image: CGImage, size: CGSize, mirrored: Bool = false
    ) throws -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw StripRenderError.contextCreationFailed }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.clip(to: bounds)
        if mirrored {
            context.translateBy(x: bounds.midX, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -bounds.midX, y: 0)
        }
        context.draw(image, in: aspectFillRect(for: image, in: bounds))

        guard let output = context.makeImage() else {
            throw StripRenderError.contextCreationFailed
        }
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
