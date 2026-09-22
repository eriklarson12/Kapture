import CoreGraphics
import Foundation
import Vision

/// Finds the faces in a stored frame and slides the crop toward them, instead
/// of always cropping about the centre.
///
/// One of the two files that import Vision (ADR-025). The request is one
/// function; the arithmetic that turns faces into a crop takes plain values and
/// is where the tests live.
enum FaceFramer {
    /// A face shorter than this fraction of the largest one is ignored. A
    /// poster on the wall or somebody far back in the room must not pull the
    /// crop away from the people in front of the camera.
    static let minimumRelativeSize: CGFloat = 0.25

    // MARK: - Detection

    /// Where the faces in `image` are, as a point in 0–1 with a bottom-left
    /// origin, or nil when Vision found none or failed.
    ///
    /// The frame handed in MUST be the stored one: true optics, unfiltered and
    /// before any backdrop. Then the answer is a function of the frame id, and
    /// the flip that `mirrorOutput` applies later turns the framed photo about
    /// its own centre.
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

    /// The centre of the union of the faces worth framing, in the space the
    /// faces are given in.
    ///
    /// The union rather than the largest face, so two people at opposite
    /// edges are both kept, or at least centred between when they cannot be.
    static func focus(of faces: [CGRect]) -> CGPoint? {
        guard let tallest = faces.map(\.height).max(), tallest > 0 else { return nil }
        let kept = faces.filter { $0.height >= tallest * minimumRelativeSize }
        guard let first = kept.first else { return nil }
        let union = kept.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: union.midX, y: union.midY)
    }

    // MARK: - Geometry

    /// The largest rect of `aspect` inside an image of `size`, centred on
    /// `focus` as far as the edges allow. Bottom-left origin, whole pixels.
    ///
    /// Only the long axis moves. With `focus` at the centre this is the region
    /// `StripRenderer.aspectFillRect` shows, so a frame with no faces and a
    /// frame whose faces are centred crop the same way.
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
