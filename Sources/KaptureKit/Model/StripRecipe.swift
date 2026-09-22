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
    /// Template fields this strip overrides. Optional, so a recipe written
    /// before styling existed still decodes.
    public var style: StripStyle?
    /// Whether the output is mirrored. On by default, because the live preview
    /// and the review beat both show the subject mirrored and a strip that came
    /// out the other way round would contradict what they just watched. The
    /// stored frame is always true optics; this is the only thing that flips it.
    public var mirrorOutput: Bool
    /// What to paint behind the person, when Vision can find one. Nil is the
    /// common case: the photograph keeps the room it was shot in.
    ///
    /// It lives here rather than on `StripStyle` because `nil` there means
    /// "follow the template", and a template can neither carry a picture
    /// (ADR-012) nor say anything about what is behind a subject.
    public var backdrop: StripBackground?
    /// Whether the crop slides toward the faces in each photo rather than
    /// centring. Optional so packages written before it still decode, and nil
    /// is off: a strip already on disk keeps the crop it was printed with.
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

    /// Normalizes a timestamp to the value its own serialized form decodes to.
    ///
    /// Rounding to the millisecond is not enough: `ISO8601DateFormatter` does
    /// calendar math on the way back and lands on a neighbouring `Double`, so
    /// 800000000.123 returns as 800000000.1229999 and a decoded recipe compares
    /// unequal to the one in memory. Formatting and reparsing yields a fixed
    /// point of the round trip, which is the only value guaranteed stable.
    static func storable(_ date: Date) -> Date {
        let formatter = RecipeCoding.formatter()
        return formatter.date(from: formatter.string(from: date)) ?? date
    }
}
