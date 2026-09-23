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
            // Save and Print belong in the File menu on macOS, and both keys
            // have to work from anywhere in the window — including kiosk mode,
            // which has no buttons to hang a shortcut on. Cmd-S used to live on
            // the Save split button; two owners of one key would fire twice, so
            // the button kept its click and gave up the key. Copy deliberately
            // stays out of the Edit menu: replacing that group would take Cut
            // and Paste with it, and the caption field needs both.
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
