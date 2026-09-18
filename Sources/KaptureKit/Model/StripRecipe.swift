import Foundation

/// A finished strip stored as its inputs rather than as a flattened image: the
/// frames that went into it, plus the template and settings used to arrange
/// them.
///
/// This is the core storage decision. Because nothing is baked, re-editing is
/// lossless, a template edit re-renders every past strip, and a recipe is small
/// enough to share as a file. Frames are referenced by id and resolved against
/// the frame store, so the JSON stays tiny.
public struct StripRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var templateID: String
    public var frameIDs: [UUID]
    public var filter: PhotoFilter
    public var caption: String?
    /// Whether the output is mirrored. Independent of the preview, which is
    /// always mirrored because that is what people expect to see of themselves.
    public var mirrorOutput: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        templateID: String,
        frameIDs: [UUID],
        filter: PhotoFilter = .none,
        caption: String? = nil,
        mirrorOutput: Bool = false
    ) {
        self.id = id
        self.createdAt = Self.storable(createdAt)
        self.templateID = templateID
        self.frameIDs = frameIDs
        self.filter = filter
        self.caption = caption
        self.mirrorOutput = mirrorOutput
    }

    /// Rounds to the millisecond, the finest resolution the stored ISO 8601
    /// timestamp can express. Without this a recipe decoded from disk compares
    /// unequal to the one in memory, which would break undo, dedupe, and any
    /// test that asserts a round-trip.
    static func storable(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate * 1000).rounded() / 1000)
    }
}
