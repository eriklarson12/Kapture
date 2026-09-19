import KaptureKit
import SwiftUI

/// Shell layout: viewport on the left, inspector on the right. Chrome stays
/// achromatic so nothing competes with the photos. See docs/design-system.md.
struct ContentView: View {
    let model: BoothModel

    var body: some View {
        HSplitView {
            ViewportView(model: model)
                .frame(minWidth: 560)
            InspectorView(model: model)
                .frame(width: 280)
        }
    }
}
