import AppKit
import SwiftUI

/// The capture flash. This is the one piece of delight in the app and it earns
/// its place by doubling as fill light for the subject.
///
/// A full-screen white flash is a genuine hazard for photosensitive users, so
/// when Reduce Motion is set this degrades to a border pulse instead. That
/// check is required by docs/design-system.md, not optional polish.
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

    /// How long the flash is held at full strength. Short enough to read as a
    /// shutter rather than a stutter.
    static let duration: Duration = .milliseconds(80)
}
