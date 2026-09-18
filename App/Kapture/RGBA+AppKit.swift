import AppKit
import KaptureKit
import SwiftUI

/// The bridge between the engine's `RGBA` and SwiftUI's `Color`.
///
/// It lives app-side on purpose: `RGBA` exists precisely so a template can carry
/// a colour through JSON without the engine linking AppKit. This file is where
/// that cost is paid back.
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
