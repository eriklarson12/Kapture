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
            .padding([.top, .horizontal], 24)
            .padding(.bottom, Self.controlsClearance)
            .accessibilityLabel("Photo strip preview")
    }

    /// The run controls overlay the viewport's bottom edge: a 44pt row on 24pt
    /// of padding. The strip MUST stop above them, or they sit on its caption.
    private static let controlsClearance: CGFloat = 24 + 44 + 24
}
