import Foundation

/// Nothing is baked, so re-editing is lossless, a template edit re-renders
/// every past strip, and the JSON stays tiny by referencing frames by id.
public struct StripRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var templateID: String
    public var frameIDs: [UUID]
    public var filter: PhotoFilter
    public var caption: String?
    /// Template fields this strip overrides. Optional, so a recipe written
    /// before styling existed still decodes.
    public var style: StripStyle?
    /// On by default — preview and review both show the subject mirrored;
    /// the stored frame is true optics, and this is the only thing that flips it.
    public var mirrorOutput: Bool
    /// Nil keeps the room as shot. Lives here, not `StripStyle`, since nil
    /// there means "follow the template," and a template can't carry a picture.
    public var backdrop: StripBackground?
    /// Optional so packages written before it still decode; nil is off, so
    /// a strip already on disk keeps the crop it was printed with.
    public var faceFraming: Bool?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        templateID: String,
        frameIDs: [UUID],
        filter: PhotoFilter = .none,
        caption: String? = nil,
        style: StripStyle? = nil,
        mirrorOutput: Bool = true,
        backdrop: StripBackground? = nil,
        faceFraming: Bool? = nil
    ) {
        self.id = id
        self.createdAt = Self.storable(createdAt)
        self.templateID = templateID
        self.frameIDs = frameIDs
        self.filter = filter
        self.caption = caption
        self.style = style
        self.mirrorOutput = mirrorOutput
        self.backdrop = backdrop
        self.faceFraming = faceFraming
    }

    /// Rounding to the millisecond isn't enough — `ISO8601DateFormatter`'s
    /// calendar math lands on a neighbouring `Double`. Format-and-reparse is the fixed point.
    static func storable(_ date: Date) -> Date {
        let formatter = RecipeCoding.formatter()
        return formatter.date(from: formatter.string(from: date)) ?? date
    }
}
