import CoreGraphics
import Foundation

public enum PDFRenderError: Error, Equatable {
    case contextCreationFailed
    /// A page with nowhere to put the strip, which would otherwise be written
    /// as a blank sheet and noticed at the printer.
    case emptySheet
}

/// A strip as a page rather than as pixels. The media box is in points, so a
/// 2x6 strip measures two by six inches however it's opened; only the photos are images.
public enum PDFRenderer {
    /// One strip, one page, at the template's own size.
    public static func page(_ strip: ResolvedStrip) throws -> Data {
        let box = CGRect(origin: .zero, size: strip.template.canvasSize)
        return try document(mediaBox: box) { context in
            try strip.draw(into: context)
        }
    }

    /// Copies of one strip tiled onto a sheet for printing and cutting.
    public static func sheet(_ strip: ResolvedStrip, layout: SheetLayout) throws -> Data {
        guard !layout.placements(for: strip.template).isEmpty else {
            throw PDFRenderError.emptySheet
        }
        let box = CGRect(origin: .zero, size: layout.pageSize)
        return try document(mediaBox: box) { context in
            try layout.draw(strip, into: context)
        }
    }

    /// A one-page PDF built by `body`. `closePDF()` must come before the data
    /// is read, or the buffer comes back truncated — a file that looks fine but won't open.
    private static func document(
        mediaBox: CGRect, _ body: (CGContext) throws -> Void
    ) throws -> Data {
        var box = mediaBox
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw PDFRenderError.contextCreationFailed }

        context.beginPDFPage([kCGPDFContextMediaBox: mediaBox] as CFDictionary)
        try body(context)
        context.endPDFPage()
        context.closePDF()
        return buffer as Data
    }
}
