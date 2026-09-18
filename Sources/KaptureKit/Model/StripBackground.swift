import CoreGraphics
import Foundation

/// What fills the canvas behind the photos.
///
/// This was a bare `RGBA` until gradients arrived. The decoder below still
/// accepts that shape, which is what keeps every template and every styled
/// strip written before this type existed readable.
public enum StripBackground: Equatable, Sendable {
    case solid(RGBA)
    /// `angle` is in degrees, measured counter-clockwise from left-to-right.
    /// One convention, stated here and asserted in the tests, because a
    /// gradient that silently rotates between builds is not re-renderable.
    case linearGradient(from: RGBA, to: RGBA, angle: CGFloat)
    /// An image in the strip's own package (ADR-012), named by asset id.
    case image(id: UUID)

    /// The colour to reach for when only one is wanted, such as seeding a
    /// picker that has just been switched to solid.
    public var representativeColor: RGBA {
        switch self {
        case .solid(let color): color
        case .linearGradient(let from, _, _): from
        case .image: .paper
        }
    }
}

extension StripBackground: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, color, from, to, angle, id
    }

    private enum Kind: String, Codable {
        case solid, linearGradient, image
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let color):
            try container.encode(Kind.solid, forKey: .kind)
            try container.encode(color, forKey: .color)
        case .linearGradient(let from, let to, let angle):
            try container.encode(Kind.linearGradient, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(angle, forKey: .angle)
        case .image(let id):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }

    /// Hand-written rather than synthesized for two reasons. The synthesized
    /// form for an enum with associated values nests everything under `_0`, and
    /// `recipe.json` is a file people are meant to be able to open. And the
    /// fallback below is the migration: a document written before this type
    /// existed holds a bare `RGBA` here, and must still decode.
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let kind = try? container.decode(Kind.self, forKey: .kind) {
            switch kind {
            case .solid:
                self = .solid(try container.decode(RGBA.self, forKey: .color))
            case .linearGradient:
                self = .linearGradient(
                    from: try container.decode(RGBA.self, forKey: .from),
                    to: try container.decode(RGBA.self, forKey: .to),
                    angle: try container.decode(CGFloat.self, forKey: .angle)
                )
            case .image:
                self = .image(id: try container.decode(UUID.self, forKey: .id))
            }
            return
        }
        self = .solid(try RGBA(from: decoder))
    }
}
