import KaptureKit
import SwiftUI

/// Shell layout: live viewport on the left, inspector on the right. Chrome
/// stays achromatic so nothing competes with the photos. See
/// docs/design-system.md.
struct ContentView: View {
    @State private var camera = AVFoundationCamera()
    @State private var templateID = BuiltInTemplates.classicStrip.id
    @State private var sequence = CaptureSequence.standard

    /// Templates are addressed by id so the picker selects one rather than
    /// editing the selected one's identity.
    private var template: StripTemplate {
        BuiltInTemplates.template(id: templateID) ?? BuiltInTemplates.classicStrip
    }

    var body: some View {
        HSplitView {
            ViewportView(camera: camera, template: template, sequence: sequence)
                .frame(minWidth: 560)
            InspectorView(templateID: $templateID, sequence: $sequence)
                .frame(width: 280)
        }
    }
}
