import AppKit
import SwiftUI

/// A full-screen white flash is a genuine hazard for photosensitive users, so
/// when Reduce Motion is set this degrades to a border pulse instead.
struct FlashOverlay: View {
    let isFlashing: Bool

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Group {
            if reduceMotion {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(.white, lineWidth: isFlashing ? 8 : 0)
            } else {
                Color.white.opacity(isFlashing ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
