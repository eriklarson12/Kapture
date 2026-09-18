import SwiftUI

/// The finished strip, on black, with nothing around it. No border, no shadow,
/// no rounded corner: the image meets the panel edge directly, and the only
/// frame it has is the one the template drew. docs/design-system.md.
struct StripPreviewView: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(24)
            .accessibilityLabel("Photo strip preview")
    }
}
