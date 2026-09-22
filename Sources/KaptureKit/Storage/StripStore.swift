import CoreGraphics
import Foundation

public enum StripStoreError: Error, Equatable {
    case notFound(UUID)
    case missingFrame(UUID)
    case frameIndexOutOfRange(Int)
    case missingAsset(UUID)
}

/// Strips on disk. One strip is one package directory holding its recipe and
/// its frames (ADR-011), so deleting a strip is a single filesystem operation
/// and no frame is ever shared between two strips.
///
/// ```
/// <root>/Strips/<recipe-uuid>.kapturestrip/
///     recipe.json
///     frames/<frame-uuid>.png
///     assets/<asset-uuid>.png
/// ```
///
/// `assets/` holds pictures the strip refers to but did not shoot, currently a
/// background image (ADR-012). Same lifetime as the strip, deleted with it,
/// never shared — the reasoning ADR-011 applied to frames, one directory over.
///
/// `root` is injected: the app passes Application Support, tests pass a
/// temporary directory.
public struct StripStore: Sendable {
    public static let packageExtension = "kapturestrip"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var stripsURL: URL {
        root.appending(path: "Strips", directoryHint: .isDirectory)
    }

    public func packageURL(for id: UUID) -> URL {
        stripsURL.appending(
            path: "\(id.uuidString).\(Self.packageExtension)",
            directoryHint: .isDirectory
        )
    }

    /// Writes the frames and a recipe describing them, and returns that recipe.
    /// Frames are stored in `index` order, which is the order the renderer zips
    /// them against `photoRects()`.
    @discardableResult
    public func save(
        frames: [CaptureFrame],
        templateID: String,
        filter: PhotoFilter = .none,
        caption: String? = nil,
        style: StripStyle? = nil,
        mirrorOutput: Bool = true,
        backdrop: StripBackground? = nil,
        faceFraming: Bool? = nil
    ) throws -> StripRecipe {
        let ordered = frames.sorted { $0.index < $1.index }
        let recipe = StripRecipe(
            templateID: templateID,
            frameIDs: ordered.map(\.id),
            filter: filter,
            caption: caption,
            style: style,
            mirrorOutput: mirrorOutput,
            backdrop: backdrop,
            faceFraming: faceFraming
        )

        let manager = FileManager.default
        try manager.createDirectory(at: stripsURL, withIntermediateDirectories: true)

        // Built aside and moved into place, so a crash mid-write cannot leave a
        // half-written package for `listRecipes()` to trip over. The staging
        // name is dot-prefixed and carries no package extension, so a leftover
        // is invisible to the listing.
        let staging = stripsURL.appending(
            path: ".staging-\(recipe.id.uuidString)", directoryHint: .isDirectory
        )
        try manager.createDirectory(
            at: staging.appending(path: "frames", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? manager.removeItem(at: staging) }

        for frame in ordered {
            let data = try ImageCodec.encodePNG(frame.image)
            try data.write(to: staging.appending(path: "frames/\(frame.id.uuidString).png"))
        }
        try RecipeCoding.encoder()
            .encode(recipe)
            .write(to: staging.appending(path: "recipe.json"))

        let destination = packageURL(for: recipe.id)
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: staging, to: destination)
        return recipe
    }

    /// Rewrites a package's recipe in place, leaving the frames alone. Every
    /// edit after the shot goes through here: template, style, caption, mirror.
    ///
    /// A single small file needs no staging directory of its own; `.atomic`
    /// already writes aside and renames. The directory staging in `save` exists
    /// because a package is many files, not because a write is risky.
    public func update(_ recipe: StripRecipe) throws {
        let package = packageURL(for: recipe.id)
        guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
            throw StripStoreError.notFound(recipe.id)
        }
        try RecipeCoding.encoder()
            .encode(recipe)
            .write(to: package.appending(path: "recipe.json"), options: .atomic)
    }

    /// Swaps one frame inside an existing package and returns the recipe that
    /// names it. The old frame is removed: frames are private to their strip
    /// (ADR-011), so nothing else can be pointing at it.
    ///
    /// The order is the whole of the correctness here. The new frame is
    /// written, then the recipe that points at it, then the old frame is
    /// removed. A crash after the recipe write leaves an orphan file, which is
    /// invisible and costs a couple of megabytes; a crash after an early delete
    /// would leave a strip that cannot render at all.
    public func replaceFrame(
        _ image: CGImage, at index: Int, in recipe: StripRecipe
    ) throws -> StripRecipe {
        guard recipe.frameIDs.indices.contains(index) else {
            throw StripStoreError.frameIndexOutOfRange(index)
        }
        let package = packageURL(for: recipe.id)
        guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
            throw StripStoreError.notFound(recipe.id)
        }

        let replaced = recipe.frameIDs[index]
        let arrival = UUID()
        try ImageCodec.encodePNG(image).write(
            to: frameURL(recipeID: recipe.id, frameID: arrival), options: .atomic
        )

        var updated = recipe
        updated.frameIDs[index] = arrival
        try update(updated)

        // The strip is already correct by this point, so a failure to tidy up
        // must not throw away a retake the user just sat through.
        try? FileManager.default.removeItem(
            at: frameURL(recipeID: recipe.id, frameID: replaced)
        )
        return updated
    }

    /// Copies an image into a strip's own package and returns the id that
    /// names it. The directory is created on first use, so a strip that never
    /// wanted one does not carry an empty folder.
    public func saveAsset(_ image: CGImage, in id: UUID) throws -> UUID {
        let package = packageURL(for: id)
        guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
            throw StripStoreError.notFound(id)
        }
        try FileManager.default.createDirectory(
            at: package.appending(path: "assets", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let assetID = UUID()
        try ImageCodec.encodePNG(image).write(
            to: assetURL(recipeID: id, assetID: assetID), options: .atomic
        )
        return assetID
    }

    public func loadAsset(_ assetID: UUID, in id: UUID) throws -> CGImage {
        guard let data = try? Data(contentsOf: assetURL(recipeID: id, assetID: assetID)) else {
            throw StripStoreError.missingAsset(assetID)
        }
        return try ImageCodec.decodePNG(data)
    }

    public func load(id: UUID) throws -> StripRecipe {
        let url = packageURL(for: id).appending(path: "recipe.json")
        guard let data = try? Data(contentsOf: url) else {
            throw StripStoreError.notFound(id)
        }
        return try RecipeCoding.decoder().decode(StripRecipe.self, from: data)
    }

    /// Frames in `recipe.frameIDs` order, ready to hand to the renderer.
    public func loadFrames(for recipe: StripRecipe) throws -> [CGImage] {
        try recipe.frameIDs.map { frameID in
            let url = frameURL(recipeID: recipe.id, frameID: frameID)
            guard let data = try? Data(contentsOf: url) else {
                throw StripStoreError.missingFrame(frameID)
            }
            return try ImageCodec.decodePNG(data)
        }
    }

    /// Every stored strip, newest first. Packages that fail to decode are
    /// skipped rather than fatal: one bad strip must not hide the rest.
    public func listRecipes() throws -> [StripRecipe] {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: stripsURL, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == Self.packageExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url.appending(path: "recipe.json")) else {
                    return nil
                }
                return try? RecipeCoding.decoder().decode(StripRecipe.self, from: data)
            }
            // Ties break on id so the order is total. Two strips cannot really
            // share a millisecond — a run takes seconds — but an arbitrary
            // order for equal keys is a flake waiting for a fast machine.
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt > $1.createdAt
            }
    }

    public func delete(id: UUID) throws {
        let url = packageURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw StripStoreError.notFound(id)
        }
        try FileManager.default.removeItem(at: url)
    }

    func frameURL(recipeID: UUID, frameID: UUID) -> URL {
        packageURL(for: recipeID).appending(path: "frames/\(frameID.uuidString).png")
    }

    func assetURL(recipeID: UUID, assetID: UUID) -> URL {
        packageURL(for: recipeID).appending(path: "assets/\(assetID.uuidString).png")
    }
}
