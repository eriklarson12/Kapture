import SwiftUI

@main
struct KaptureApp: App {
    /// Held here rather than in `ContentView` so the File menu can reach it.
    @State private var model = BoothModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            // Print belongs in the File menu on macOS, and Cmd-P has to work
            // from anywhere in the window. Copy deliberately stays out of the
            // Edit menu: replacing that group would take Cut and Paste with it,
            // and the caption field needs both.
            CommandGroup(replacing: .printItem) {
                Button("Print\u{2026}") { Task { await model.printStrip() } }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(model.strip == nil || model.isExporting)
            }
        }
    }
}
