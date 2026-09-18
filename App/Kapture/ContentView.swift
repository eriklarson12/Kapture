import KaptureKit
import SwiftUI

/// Shell layout: live viewport on the left, inspector on the right, gallery
/// along the bottom. Chrome stays achromatic so nothing competes with the
/// photos. See docs/design-system.md.
struct ContentView: View {
    @State private var template = BuiltInTemplates.classicStrip
    @State private var sequence = CaptureSequence.standard

    var body: some View {
        HSplitView {
            ViewportView(template: template, sequence: sequence)
                .frame(minWidth: 560)
            InspectorView(template: $template, sequence: $sequence)
                .frame(width: 280)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
