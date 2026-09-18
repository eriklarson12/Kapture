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
            // Timestamps spelled out. Two saves can land in the same
            // millisecond, and then the assertion below is testing the sort's
            // tie-break rather than the ordering it claims to test.
            var older = try store.save(frames: makeFrames(1), templateID: "classic-strip")
            older.createdAt = StripRecipe.storable(Date(timeIntervalSinceNow: -60))
            try store.update(older)
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
            recipe.style = StripStyle(background: .solid(RGBA(red: 0.9, green: 0.9, blue: 0.85)))
            try store.update(recipe)

            let reloaded = try store.load(id: recipe.id)
            #expect(reloaded == recipe)
            #expect(reloaded.caption == "Summer 2026")
            #expect(reloaded.style?.background == .solid(RGBA(red: 0.9, green: 0.9, blue: 0.85)))

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

    // MARK: - Single-frame retake

    private func frameFileCount(_ store: StripStore, _ id: UUID) throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: store.packageURL(for: id).appending(path: "frames", directoryHint: .isDirectory),
            includingPropertiesForKeys: nil
        ).count
    }

    @Test("replacing a frame swaps one id and leaves the rest")
    func replaceFrameSwapsOneID() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let replacement = TestImage.solid(width: 64, height: 48, gray: 0.9)
            let updated = try store.replaceFrame(replacement, at: 2, in: saved)

            #expect(updated.frameIDs[2] != saved.frameIDs[2])
            #expect(updated.frameIDs.enumerated().allSatisfy { index, id in
                index == 2 || id == saved.frameIDs[index]
            })
            #expect(try store.load(id: saved.id) == updated)
        }
    }

    /// The old file has to go, or a party's worth of retakes quietly doubles
    /// the strip on disk. Frames are private to their strip (ADR-011), so
    /// nothing else can be pointing at it.
    @Test("replacing a frame leaves no orphan behind")
    func replaceFrameRemovesTheOldFile() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let updated = try store.replaceFrame(
                TestImage.solid(width: 64, height: 48, gray: 0.9), at: 0, in: saved
            )

            #expect(try frameFileCount(store, saved.id) == 4)
            #expect(!FileManager.default.fileExists(
                atPath: store.frameURL(recipeID: saved.id, frameID: saved.frameIDs[0])
                    .path(percentEncoded: false)
            ))
            #expect(try store.loadFrames(for: updated).count == 4)
        }
    }

    @Test("a replaced frame is the image that comes back")
    func replaceFramePersistsPixels() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let replacement = TestImage.solid(width: 64, height: 48, gray: 0.9)
            let updated = try store.replaceFrame(replacement, at: 1, in: saved)

            let frames = try store.loadFrames(for: updated)
            #expect(TestImage.pixels(frames[1]) == TestImage.pixels(replacement))
            #expect(TestImage.red(frames[0], x: 0, y: 0) != TestImage.red(frames[1], x: 0, y: 0))
        }
    }

    @Test("an index outside the strip names itself")
    func replaceFrameOutOfRange() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let replacement = TestImage.solid(width: 64, height: 48, gray: 0.9)
            #expect(throws: StripStoreError.frameIndexOutOfRange(4)) {
                try store.replaceFrame(replacement, at: 4, in: saved)
            }
            #expect(throws: StripStoreError.frameIndexOutOfRange(-1)) {
                try store.replaceFrame(replacement, at: -1, in: saved)
            }
        }
    }

    @Test("replacing a frame of a strip that is gone throws")
    func replaceFrameUnknownStrip() throws {
        try withStore { store in
            let orphan = StripRecipe(templateID: "classic-strip", frameIDs: [UUID()])
            #expect(throws: StripStoreError.notFound(orphan.id)) {
                try store.replaceFrame(
                    TestImage.solid(width: 8, height: 8), at: 0, in: orphan
                )
            }
        }
    }

    // MARK: - Assets

    @Test("an asset saved into a package loads back, pixel for pixel")
    func assetRoundTrip() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let picture = TestImage.asymmetric(width: 32, height: 24)
            let assetID = try store.saveAsset(picture, in: saved.id)

            let loaded = try store.loadAsset(assetID, in: saved.id)
            #expect(TestImage.pixels(loaded) == TestImage.pixels(picture))
        }
    }

    /// Assets live inside the strip, so deleting the strip takes them with it.
    /// That is the whole of ADR-012: nothing is shared, nothing is counted.
    @Test("deleting a strip takes its assets with it")
    func deleteRemovesAssets() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let assetID = try store.saveAsset(TestImage.solid(width: 8, height: 8), in: saved.id)
            try store.delete(id: saved.id)

            #expect(!FileManager.default.fileExists(
                atPath: store.assetURL(recipeID: saved.id, assetID: assetID)
                    .path(percentEncoded: false)
            ))
        }
    }

    @Test("an asset that is not there names itself")
    func missingAsset() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            let absent = UUID()
            #expect(throws: StripStoreError.missingAsset(absent)) {
                try store.loadAsset(absent, in: saved.id)
            }
        }
    }

    /// A strip that never wanted a picture must not carry an empty folder for
    /// one, or every package on disk grows a directory nothing reads.
    @Test("a strip with no assets has no assets folder")
    func noAssetsFolderByDefault() throws {
        try withStore { store in
            let saved = try store.save(frames: makeFrames(), templateID: "classic-strip")
            #expect(!FileManager.default.fileExists(
                atPath: store.packageURL(for: saved.id)
                    .appending(path: "assets", directoryHint: .isDirectory)
                    .path(percentEncoded: false)
            ))
        }
    }
}
