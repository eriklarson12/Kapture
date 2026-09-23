import CoreGraphics
import Foundation

/// This was a bare `RGBA` until gradients arrived; the decoder still accepts
/// that shape, so strips written before this type existed stay readable.
public enum StripBackground: Equatable, Sendable {
    case solid(RGBA)
    /// `angle` is degrees counter-clockwise from left-to-right — asserted in
    /// tests, since a silently rotating convention isn't re-renderable.
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

    /// Hand-written, not synthesized — synthesis nests an enum's associated
    /// values under `_0`, and the fallback below still decodes a bare `RGBA`.
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
