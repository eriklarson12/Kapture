import KaptureKit
import SwiftUI

/// Shell layout: viewport on the left, inspector on the right. Chrome stays
/// achromatic so nothing competes with the photos. See docs/design-system.md.
struct ContentView: View {
    @Bindable var model: BoothModel

    var body: some View {
        // The inspector is removed, not the layout around it: branching the whole
        // view would give `ViewportView` a new identity and restart the camera.
        HSplitView {
            ViewportView(model: model)
                .frame(minWidth: 560)
            if !model.isKiosk {
                InspectorView(model: model)
                    .frame(width: 280)
            }
        }
        .kiosk(isOn: $model.isKiosk)
        #if DEBUG
        .task { await DemoMode.play(model) }
        #endif
        // A sheet rather than more inspector: the inspector edits this strip,
        // and the editor edits a file that every strip naming it will follow.
        .sheet(item: $model.editingTemplate) { edit in
            TemplateEditorView(model: model, edit: edit)
        }
        // `initial` covers the cold launch, where the file arrives before this
        // view exists; the same closure then covers an app already running.
        .onChange(of: AppDelegate.opened.urls, initial: true) { _, urls in
            guard !urls.isEmpty else { return }
            let taken = AppDelegate.opened.take()
            Task { for url in taken { await model.importTemplate(at: url) } }
        }
    }
}
