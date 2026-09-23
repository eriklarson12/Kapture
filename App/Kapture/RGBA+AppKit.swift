import AppKit
import KaptureKit
import SwiftUI

/// Lives app-side on purpose: `RGBA` exists so a template can carry a colour
/// through JSON without the engine linking AppKit.
extension RGBA {
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Converted through sRGB, because a display-P3 pick would otherwise store
    /// components that mean something different when the strip is printed.
    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }
}
