import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("PersonMaskStore")
struct PersonMaskStoreTests {
    /// A counting segmenter. The claim is about how often Vision is asked, and
    /// nothing else in the project can see that.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func tick() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    @Test("a frame is segmented once however many times it is rendered")
    func remembersAMask() {
        let counter = Counter()
        let store = PersonMaskStore(segment: { image in
            counter.tick()
            return TestImage.mask(width: image.width, height: image.height)
        })

        let frame = TestImage.asymmetric()
        let id = UUID()
        for _ in 0..<5 { _ = store.mask(for: frame, id: id) }

        #expect(counter.count == 1)
    }

    /// Without this, an empty room re-runs Vision on every tick of a colour
    /// drag — the one case where there is no mask to hold onto.
    @Test("a frame with nobody in it is remembered too")
    func remembersTheAbsenceOfAMask() {
        let counter = Counter()
        let store = PersonMaskStore(segment: { _ in
            counter.tick()
            return nil
        })

        let frame = TestImage.solid(width: 64, height: 64)
        let id = UUID()
        for _ in 0..<5 { #expect(store.mask(for: frame, id: id) == nil) }

        #expect(counter.count == 1)
    }

    @Test("two frames get two masks")
    func keysOnTheFrame() {
        let counter = Counter()
        let store = PersonMaskStore(segment: { image in
            counter.tick()
            return TestImage.mask(width: image.width, height: image.height)
        })

        let frame = TestImage.asymmetric()
        _ = store.mask(for: frame, id: UUID())
        _ = store.mask(for: frame, id: UUID())

        #expect(counter.count == 2)
    }

    @Test("the store forgets wholesale rather than growing without limit")
    func isBounded() {
        let store = PersonMaskStore(segment: { image in
            TestImage.mask(width: image.width, height: image.height)
        })
        let frame = TestImage.solid(width: 32, height: 32)
        for _ in 0..<200 { _ = store.mask(for: frame, id: UUID()) }
        #expect(store.count <= 32)
    }
}

@Suite("FaceStore")
struct FaceStoreTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func tick() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    @Test("a frame's faces are found once however many times it is rendered")
    func remembersAFocus() {
        let counter = Counter()
        let store = FaceStore(detect: { _ in
            counter.tick()
            return CGPoint(x: 0.2, y: 0.5)
        })
        let frame = TestImage.asymmetric()
        let id = UUID()
        for _ in 0..<5 { _ = store.focus(for: frame, id: id) }
        #expect(counter.count == 1)
    }

    @Test("a frame with no faces is remembered too")
    func remembersNoFaces() {
        let counter = Counter()
        let store = FaceStore(detect: { _ in
            counter.tick()
            return nil
        })
        let frame = TestImage.solid(width: 64, height: 64)
        let id = UUID()
        for _ in 0..<5 { #expect(store.focus(for: frame, id: id) == nil) }
        #expect(counter.count == 1)
    }

    @Test("the store forgets wholesale rather than growing without limit")
    func isBounded() {
        let store = FaceStore(detect: { _ in CGPoint(x: 0.5, y: 0.5) })
        let frame = TestImage.solid(width: 32, height: 32)
        for _ in 0..<200 { _ = store.focus(for: frame, id: UUID()) }
        #expect(store.count <= 32)
    }
}
