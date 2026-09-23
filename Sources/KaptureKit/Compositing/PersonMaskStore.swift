import CoreGraphics
import Foundation

/// Keyed by frame id (a retake mints a new one, so hits never go stale).
/// `@unchecked Sendable` (ADR-009): every mutable field stays inside `lock`.
final class FrameMemo<Value>: @unchecked Sendable {
    /// Cleared wholesale rather than LRU-evicted: a miss just costs one
    /// re-ask, and an LRU costs a second data structure to keep correct.
    static var limit: Int { 32 }

    private let lock = NSLock()
    private let compute: @Sendable (CGImage) -> Value?
    /// `Value?` so "found nothing" is remembered too, not just a miss.
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

        // Computed outside the lock — a duplicated computation from a race
        // is cheap; holding it across a Vision request would stall everything.
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

/// Segmenting four full-resolution frames costs the better part of a
/// second, and `restyle` re-renders on every tick of a colour drag.
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
