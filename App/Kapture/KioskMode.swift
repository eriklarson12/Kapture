import AppKit
import Combine
import SwiftUI

/// Puts the window in and out of fullscreen for kiosk mode.
///
/// macOS 14 SwiftUI has no fullscreen API, and an `NSWindow` is the only thing
/// that can enter it, so this reaches for one the way `CameraPreview` reaches
/// for AppKit.
private struct KioskModifier: ViewModifier {
    @Binding var isKiosk: Bool
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0 })
            .onChange(of: isKiosk) { _, wanted in
                guard let window,
                      window.styleMask.contains(.fullScreen) != wanted else { return }
                window.toggleFullScreen(nil)
            }
            // The green button and ⌃⌘F leave fullscreen without asking. Without
            // this the flag goes stale, and the inspector never comes home.
            .onReceive(NotificationCenter.default.publisher(
                for: NSWindow.didExitFullScreenNotification
            )) { note in
                if note.object as? NSWindow === window { isKiosk = false }
            }
    }
}

extension View {
    func kiosk(isOn: Binding<Bool>) -> some View {
        modifier(KioskModifier(isKiosk: isOn))
    }
}

/// Hands up the `NSWindow` a SwiftUI view ended up in. The window does not
/// exist while the view is being made, so it is reported from `viewDidMoveTo`
/// rather than read once.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
