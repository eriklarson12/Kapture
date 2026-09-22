import CoreGraphics
import Foundation

/// Person masks already computed, keyed by frame id.
///
/// Segmenting four full-resolution frames costs the better part of a second,
/// and `restyle` re-renders on every tick of a colour drag. The key is correct
/// by construction: a frame id names an immutable file, because a retake mints
/// a new id rather than rewriting one, so a hit can never be stale.
///
/// Injected rather than global, the way `StripStore` takes its root and
/// `CaptureRunner` takes its clock. `@unchecked Sendable` over a lock is the
/// one unsafe assertion here and it is stated in this one place (ADR-009's
/// pattern): `RecipeRenderer` is `Sendable` and is captured into a detached
/// task to render off the main actor.
public final class PersonMaskStore: @unchecked Sendable {
    /// Bounded so a long gallery session cannot grow without limit. Cleared
    /// wholesale rather than evicted least-recently-used: a miss costs one
    /// segmentation, and an LRU costs a second data structure to keep correct.
    private static let limit = 32

    private let lock = NSLock()
    private let segment: @Sendable (CGImage) -> CGImage?
    /// The value is itself optional, so "Vision found nobody in this frame" is
    /// remembered too. Without that, an empty room re-segments on every render.
    private var masks: [UUID: CGImage?] = [:]

    public init() {
        self.segment = { BackdropRenderer.mask(for: $0) }
    }

    init(segment: @escaping @Sendable (CGImage) -> CGImage?) {
        self.segment = segment
    }

    func mask(for image: CGImage, id: UUID) -> CGImage? {
        lock.lock()
        if let remembered = masks[id] {
            lock.unlock()
            return remembered
        }
        lock.unlock()

        // Segmentation runs outside the lock. Two renders of one frame racing
        // is a duplicated computation, which is cheap; holding a lock across a
        // Vision request would stall every other frame behind it.
        let mask = segment(image)

        lock.lock()
        defer { lock.unlock() }
        if masks.count >= Self.limit { masks.removeAll(keepingCapacity: true) }
        masks[id] = mask
        return mask
    }

    /// How many frames are remembered. For tests and for nothing else.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return masks.count
    }
}
