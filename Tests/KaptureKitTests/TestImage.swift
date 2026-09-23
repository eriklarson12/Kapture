import CoreGraphics
import Foundation

enum TestImage {
    /// A solid-colour image, so a test can assert on geometry without a camera.
    static func solid(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func frames(_ count: Int, width: Int = 640, height: Int = 480) -> [CGImage] {
        (0..<count).map { _ in solid(width: width, height: height) }
    }

    /// Black on the left half, white on the right, uniform top to bottom, so a
    /// mirror test can sample any row regardless of buffer layout.
    static func asymmetric(width: Int = 640, height: Int = 480) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    /// A device-grey mask: `personFraction` of the width white, the rest
    /// black. Grey, not sRGB, matching what `BackdropRenderer` produces.
    static func mask(
        width: Int = 640, height: Int = 480, personFraction: Double = 0.5
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let person = Int((Double(width) * personFraction).rounded())
        if person > 0 {
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: person, height: height))
        }
        return context.makeImage()!
    }

    /// A red stripe down the leftmost tenth, then black, then white. Cropping
    /// removes the stripe; squashing keeps it — the centred boundary alone can't tell them apart.
    static func edgeMarked(width: Int = 640, height: Int = 360) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 10, height: height))
        return context.makeImage()!
    }

    /// The green channel, which is 0 in both the black and the red bands of
    /// `edgeMarked` and 255 in the white one.
    static func green(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        pixels(image)[y * image.width * 4 + x * 4 + 1]
    }

    /// Raw RGBA bytes in a fixed layout, so two images can be compared without
    /// depending on the format a decoder happened to choose.
    static func pixels(_ image: CGImage) -> [UInt8] {
        let bytesPerRow = image.width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
        return buffer
    }

    static func red(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        pixels(image)[y * image.width * 4 + x * 4]
    }
}
