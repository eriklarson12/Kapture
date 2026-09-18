import SwiftUI

/// The countdown before a shot. A number, changing. No spin, no pulse: the
/// design system allows exactly two pieces of motion in this app and neither of
/// them is decorative.
struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 96, weight: .light).monospacedDigit())
            .foregroundStyle(.white)
            .shadow(radius: 12)
            .accessibilityLabel("\(value) seconds until capture")
            // Announced rather than merely drawn, so the countdown is usable
            // without sight of the screen.
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    CountdownOverlay(value: 3)
        .frame(width: 400, height: 300)
        .background(.black)
}
