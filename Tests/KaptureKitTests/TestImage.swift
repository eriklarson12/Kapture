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
}
