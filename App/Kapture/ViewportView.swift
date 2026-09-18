import KaptureKit
import SwiftUI

/// The camera feed and countdown. Preview is always mirrored because that is
/// what people expect to see of themselves; whether the *output* mirrors is a
/// separate setting on the recipe.
struct ViewportView: View {
    let template: StripTemplate
    let sequence: CaptureSequence

    var body: some View {
        ZStack {
            Color.black
            Text("Camera preview")
                .foregroundStyle(.secondary)
        }
        // TODO 1.2: host an AVCaptureVideoPreviewLayer via NSViewRepresentable.
        // TODO 1.3: overlay the countdown and the white capture flash.
    }
}
