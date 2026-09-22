import CoreGraphics
import Foundation

/// A value computed from one stored frame, remembered by that frame's id.
///
/// The key is correct by construction: a frame id names an immutable file,
/// because a retake mints a new id rather than rewriting one, so a hit can
/// never be stale. The value is itself optional, so "Vision found nothing in
/// this frame" is remembered too; without that, an empty room re-asks Vision on
/// every render.
///
/// `@unchecked Sendable` over a lock is the one unsafe assertion here and it is
/// stated in this one place (ADR-009's pattern): `RecipeRenderer` is `Sendable`
/// and is captured into a detached task to render off the main actor.
final class FrameMemo<Value>: @unchecked Sendable {
    /// Bounded so a long gallery session cannot grow without limit. Cleared
    /// wholesale rather than evicted least-recently-used: a miss costs one
    /// request, and an LRU costs a second data structure to keep correct.
    static var limit: Int { 32 }

    private let lock = NSLock()
    private let compute: @Sendable (CGImage) -> Value?
    private var values: [UUID: Value?] = [:]

    init(compute: @escaping @Sendable (CGImage) -> Value?) {
        self.compute = compute
    }

    func value(for image: CGImage, id: UUID) -> Value? {
        lock.lock()
        if let remembered = values[id] {
            lock.unlock()
            return remembered
        }
        lock.unlock()

        // Computed outside the lock. Two renders of one frame racing is a
        // duplicated computation, which is cheap; holding a lock across a
        // Vision request would stall every other frame behind it.
        let value = compute(image)

        lock.lock()
        defer { lock.unlock() }
        if values.count >= Self.limit { values.removeAll(keepingCapacity: true) }
        values[id] = value
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }
}

/// Person masks already computed, keyed by frame id.
///
/// Segmenting four full-resolution frames costs the better part of a second,
/// and `restyle` re-renders on every tick of a colour drag.
///
/// Injected rather than global, the way `StripStore` takes its root and
/// `CaptureRunner` takes its clock.
public final class PersonMaskStore: Sendable {
    private let memo: FrameMemo<CGImage>

    public init() {
        self.memo = FrameMemo { BackdropRenderer.mask(for: $0) }
    }

    init(segment: @escaping @Sendable (CGImage) -> CGImage?) {
        self.memo = FrameMemo(compute: segment)
    }

    func mask(for image: CGImage, id: UUID) -> CGImage? {
        memo.value(for: image, id: id)
    }

    /// How many frames are remembered. For tests and for nothing else.
    var count: Int { memo.count }
}

/// Face centres already found, keyed by frame id, for the same reason masks
/// are: a drag re-renders on every tick, and a frame's faces never move.
public final class FaceStore: Sendable {
    private let memo: FrameMemo<CGPoint>

    public init() {
        self.memo = FrameMemo { FaceFramer.focus(for: $0) }
    }

    init(detect: @escaping @Sendable (CGImage) -> CGPoint?) {
        self.memo = FrameMemo(compute: detect)
    }

    func focus(for image: CGImage, id: UUID) -> CGPoint? {
        memo.value(for: image, id: id)
    }

    /// How many frames are remembered. For tests and for nothing else.
    var count: Int { memo.count }
}
