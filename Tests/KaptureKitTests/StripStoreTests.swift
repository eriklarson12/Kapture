import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("StripStore")
struct StripStoreTests {
    private func withStore(_ body: (StripStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "KaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(StripStore(root: root))
    }

    private func makeFrames(_ count: Int = 4) -> [CaptureFrame] {
        (0..<count).map {
            CaptureFrame(index: $0, image: TestImage.solid(width: 64, height: 48, gray: CGFloat($0) / 10))
        }
    }

    @Test("a saved strip loads back identically")
    func roundTrip() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let loaded = try store.load(id: saved.id)
            #expect(loaded == saved)
        }
    }

    @Test("frames come back in frameIDs order, pixel for pixel")
    func frameOrderAndFidelity() throws {
        try withStore { store in
            let frames = makeFrames()
            let recipe = try store.save(frames: frames, templateID: "classic-strip")
            #expect(recipe.frameIDs == frames.map(\.id))

            let loaded = try store.loadFrames(for: recipe)
            #expect(loaded.count == 4)
            for (original, restored) in zip(frames, loaded) {
                #expect(TestImage.pixels(restored) == TestImage.pixels(original.image))
            }
        }
    }

    /// Frames arrive from the driver in order, but the store must not depend on
    /// that: `index` is the slot, and a retaken frame (item 2.5) arrives late.
    @Test("shuffled frames are stored in index order")
    func sortsByIndex() throws {
        try withStore { store in
            let frames = makeFrames()
            let recipe = try store.save(frames: frames.reversed(), templateID: "classic-strip")
            #expect(recipe.frameIDs == frames.map(\.id))
        }
    }

    @Test("a strip is one directory, and deleting it is one operation")
    func deleteRemovesPackage() throws {
        try withStore { store in
            let recipe = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let package = store.packageURL(for: recipe.id)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))

            try store.delete(id: recipe.id)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) == false)
            let listed = try store.listRecipes()
            #expect(listed.isEmpty)
        }
    }

    @Test("lists every stored strip, newest first")
    func listsNewestFirst() throws {
        try withStore { store in
            let older = try store.save(frames: makeFrames(1), templateID: "classic-strip")
            let newer = try store.save(frames: makeFrames(1), templateID: "wide-strip")

            let listed = try store.listRecipes()
            #expect(listed.count == 2)
            #expect(listed.first?.id == newer.id)
            #expect(listed.last?.id == older.id)
        }
    }

    @Test("an empty store lists nothing rather than throwing")
    func emptyStore() throws {
        try withStore { store in
            let listed = try store.listRecipes()
            #expect(listed.isEmpty)
        }
    }

    @Test("a package missing a frame file fails loudly")
    func missingFrame() throws {
        try withStore { store in
            let recipe = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let orphaned = recipe.frameIDs[1]
            try FileManager.default.removeItem(
                at: store.frameURL(recipeID: recipe.id, frameID: orphaned)
            )

            #expect(throws: StripStoreError.missingFrame(orphaned)) {
                try store.loadFrames(for: recipe)
            }
        }
    }

    @Test("loading a strip that was never saved reports which one")
    func notFound() throws {
        try withStore { store in
            let id = UUID()
            #expect(throws: StripStoreError.notFound(id)) {
                try store.load(id: id)
            }
        }
    }

    @Test("update rewrites the recipe and leaves the frames alone")
    func updateRewritesRecipe() throws {
        try withStore { store in
            var recipe = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let framesBefore = try store.loadFrames(for: recipe).map(TestImage.pixels)

            recipe.caption = "Summer 2026"
            recipe.style = StripStyle(background: RGBA(red: 0.9, green: 0.9, blue: 0.85))
            try store.update(recipe)

            let reloaded = try store.load(id: recipe.id)
            #expect(reloaded == recipe)
            #expect(reloaded.caption == "Summer 2026")
            #expect(reloaded.style?.background?.blue == 0.85)

            let framesAfter = try store.loadFrames(for: reloaded).map(TestImage.pixels)
            #expect(framesAfter == framesBefore)
        }
    }

    @Test("updating a strip that was never saved reports which one")
    func updateUnknownStrip() throws {
        try withStore { store in
            let recipe = StripRecipe(templateID: "classic-strip", frameIDs: [UUID()])
            #expect(throws: StripStoreError.notFound(recipe.id)) {
                try store.update(recipe)
            }
        }
    }

    @Test("an updated strip keeps its place in the listing")
    func updateKeepsListing() throws {
        try withStore { store in
            var recipe = try store.save(frames: makeFrames(), templateID: "classic-strip")
            recipe.templateID = "wide-strip"
            try store.update(recipe)

            let listed = try store.listRecipes()
            #expect(listed.count == 1)
            #expect(listed.first?.templateID == "wide-strip")
        }
    }
}
