import CoreGraphics
import Foundation
import Vision

/// One of two files that import Vision (ADR-025); the face-to-crop
/// arithmetic takes plain values, which is where the tests live.
enum FaceFramer {
    /// A face shorter than this fraction of the largest one is ignored, so a
    /// poster on the wall can't pull the crop away from the people in front.
    static let minimumRelativeSize: CGFloat = 0.25

    /// `image` must be the stored, true-optics frame, before any backdrop —
    /// then the answer is a function of the frame id alone.
    static func focus(for image: CGImage) -> CGPoint? {
        let request = VNDetectFaceRectanglesRequest()
        // Pinned rather than left to `defaultRevision`, which moves with the
        // OS. Same rule as the person mask (ADR-024).
        if VNDetectFaceRectanglesRequest.supportedRevisions
            .contains(VNDetectFaceRectanglesRequestRevision3) {
            request.revision = VNDetectFaceRectanglesRequestRevision3
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // A strip comes out centred rather than not at all.
            return nil
        }
        return focus(of: (request.results ?? []).map(\.boundingBox))
    }

    /// Union rather than the largest face, so two people at opposite edges
    /// are both kept, or centred between when they can't both fit.
    static func focus(of faces: [CGRect]) -> CGPoint? {
        guard let tallest = faces.map(\.height).max(), tallest > 0 else { return nil }
        let kept = faces.filter { $0.height >= tallest * minimumRelativeSize }
        guard let first = kept.first else { return nil }
        let union = kept.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: union.midX, y: union.midY)
    }

    /// Bottom-left origin, whole pixels. With `focus` centred this matches
    /// `StripRenderer.aspectFillRect`, so a faceless frame crops the same way.
    static func cropRect(imageSize size: CGSize, aspect: CGFloat, focus: CGPoint) -> CGRect {
        guard size.width >= 1, size.height >= 1, aspect > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        if size.width / size.height > aspect {
            let width = min(size.width, max(1, (size.height * aspect).rounded()))
            let x = clamped((focus.x * size.width - width / 2).rounded(), upTo: size.width - width)
            return CGRect(x: x, y: 0, width: width, height: size.height)
        }
        let height = min(size.height, max(1, (size.width / aspect).rounded()))
        let y = clamped((focus.y * size.height - height / 2).rounded(), upTo: size.height - height)
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// `image` cut down to `aspect` about `focus`. The caller then aspect-fills
    /// an image that already fits, so `StripRenderer` never learns this exists.
    static func cropped(_ image: CGImage, aspect: CGFloat, focus: CGPoint) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let rect = cropRect(imageSize: size, aspect: aspect, focus: focus)
        guard rect.size != size else { return image }
        // `cropping(to:)` counts rows from the top; the rect is bottom-left.
        let flipped = CGRect(
            x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height
        )
        return image.cropping(to: flipped) ?? image
    }

    private static func clamped(_ value: CGFloat, upTo limit: CGFloat) -> CGFloat {
        min(max(0, value), max(0, limit))
    }
}
