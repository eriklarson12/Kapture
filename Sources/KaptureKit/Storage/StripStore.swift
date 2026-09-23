import CoreGraphics
import Foundation

public enum StripStoreError: Error, Equatable {
    case notFound(UUID)
    case missingFrame(UUID)
    case frameIndexOutOfRange(Int)
    case missingAsset(UUID)
}

/// Strips on disk. One strip is one package directory holding its recipe and
/// frames (ADR-011), so deleting a strip is a single filesystem operation.
///
/// ```
/// <root>/Strips/<recipe-uuid>.kapturestrip/
///     recipe.json
///     frames/<frame-uuid>.png
///     assets/<asset-uuid>.png
/// ```
///
/// `assets/` holds pictures the strip refers to but did not shoot (a
/// background image, ADR-012) — same lifetime as the strip, never shared.
/// `root` is injected: the app passes Application Support, tests a temp directory.
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
    /// Frames are stored in `index` order, matching `photoRects()`.
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

        // Built aside and moved into place, so a crash mid-write can't leave a
        // half-written package; the dot-prefixed name also stays invisible to `listRecipes()`.
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

    /// Rewrites a package's recipe in place, leaving the frames alone. A single
    /// small file needs no staging directory; `.atomic` already writes aside and renames.
    public func update(_ recipe: StripRecipe) throws {
        let package = packageURL(for: recipe.id)
        guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
            throw StripStoreError.notFound(recipe.id)
        }
        try RecipeCoding.encoder()
            .encode(recipe)
            .write(to: package.appending(path: "recipe.json"), options: .atomic)
    }

    /// Swaps one frame and returns the recipe that names it. Order matters:
    /// write new frame, then recipe, then delete old — an early delete risks an unrenderable strip.
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

    /// Copies an image into a strip's own package and returns its id. The
    /// directory is created on first use, so a strip that never used one carries no empty folder.
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
            // Ties break on id so the order is total — an arbitrary order for
            // equal keys is a flake waiting for a fast machine.
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
