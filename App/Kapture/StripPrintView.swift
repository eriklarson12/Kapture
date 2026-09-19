import AppKit
import KaptureKit

/// The page a print job draws: the strip tiled onto its sheet.
///
/// Holds a `ResolvedStrip` rather than a recipe because AppKit redraws a
/// printed view whenever it likes, and a draw call must never go to disk.
///
/// Not flipped. `NSView` is bottom-left origin by default, which is the same
/// convention the whole engine uses, and flipping it would turn every strip
/// upside down.
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
        // The strip was resolved before this view existed, so the only thing
        // left to throw is a template that cannot render — which the user has
        // already watched fail in the viewport. There is nowhere to report it
        // from inside a draw call.
        try? layout.draw(strip, into: context)
    }
}
