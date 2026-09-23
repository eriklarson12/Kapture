import AppKit
import KaptureKit

/// Holds a `ResolvedStrip` rather than a recipe because AppKit redraws a
/// printed view whenever it likes, and a draw call must never go to disk.
final class StripPrintView: NSView {
    private let strip: ResolvedStrip
    private let layout: SheetLayout

    init(strip: ResolvedStrip, layout: SheetLayout) {
        self.strip = strip
        self.layout = layout
        super.init(frame: CGRect(origin: .zero, size: layout.pageSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StripPrintView is built in code, never from a nib")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Only an unrenderable template can throw here, and the user has already
        // watched that fail in the viewport; there's nowhere to report it from a draw call.
        try? layout.draw(strip, into: context)
    }
}
