import SwiftUI

@main
struct KaptureApp: App {
    /// Held here rather than in `ContentView` so the File menu can reach it.
    #if DEBUG
    @State private var model = BoothModel(root: DemoMode.root ?? .kaptureSupportDirectory)
    #else
    @State private var model = BoothModel()
    #endif
    /// Only so a template double-clicked in Finder has somewhere to land.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            // Both keys must work from kiosk mode, which has no buttons for a shortcut.
            // Copy stays out of the Edit menu: replacing it would take Cut/Paste too.
            CommandGroup(replacing: .saveItem) {
                Button("Save Strip\u{2026}") { Task { await model.exportStrip() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.strip == nil || model.isExporting)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print\u{2026}") { Task { await model.printStrip() } }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(model.strip == nil || model.isExporting)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button(model.isKiosk ? "Leave Kiosk Mode" : "Enter Kiosk Mode") {
                    model.isKiosk.toggle()
                }
                // Control-Command-F belongs to the system's own fullscreen.
                .keyboardShortcut("k", modifiers: [.command, .control])
            }
        }
    }
}
