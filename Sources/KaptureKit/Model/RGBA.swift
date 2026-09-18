import CoreGraphics
import Foundation

/// A colour stored as components so templates round-trip through JSON without
/// pulling AppKit into the engine.
public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts `RRGGBB` or `#RRGGBB`.
    public init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let packed = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255
        )
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension RGBA {
    public static let paper = RGBA(red: 1, green: 1, blue: 1)
    public static let ink = RGBA(red: 0.07, green: 0.07, blue: 0.07)
}
