import Foundation

/// The unguessable half of a share link: a stale one fails closed instead of
/// resolving to whoever's in front of the camera now. The one value in the project that must *not* be deterministic.
public struct ShareToken: Hashable, Sendable, CustomStringConvertible {
    public static let length = 16
    /// Lower case and digits only: typed by hand when a camera won't focus,
    /// so case is one fewer thing to get wrong.
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    public let value: String
    public var description: String { value }

    /// Refuses anything that is not a token, which is also what refuses
    /// `/s/../recipe.json` before a single byte is read from disk.
    public init?(_ text: String) {
        guard text.count == Self.length,
              text.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        value = text
    }

    private init(minted: String) {
        value = minted
    }

    public static func mint() -> ShareToken {
        var generator = SystemRandomNumberGenerator()
        let bound = UInt64(alphabet.count)
        return ShareToken(
            minted: String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: bound))] })
        )
    }
}

/// What a request path asked for. Three things, and everything else is a 404.
public enum ShareRoute: Equatable, Sendable {
    case page(ShareToken)
    case png(ShareToken)
    case gif(ShareToken)

    public var token: ShareToken {
        switch self {
        case .page(let token), .png(let token), .gif(let token): token
        }
    }

    /// `/s/<token>`, `/s/<token>/strip.png`, `/s/<token>/strip.gif`. Segments
    /// are checked positionally and the token by shape, so no path can name a file.
    public static func parse(_ path: String) -> ShareRoute? {
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" { parts.removeLast() }
        guard parts.count >= 3, parts[0] == "", parts[1] == "s",
              let token = ShareToken(parts[2]) else { return nil }

        switch parts.count {
        case 3: return .page(token)
        case 4 where parts[3] == "strip.png": return .png(token)
        case 4 where parts[3] == "strip.gif": return .gif(token)
        default: return nil
        }
    }

    /// The path a page links to, so the page and the parser cannot drift.
    public static func path(for route: ShareRoute) -> String {
        switch route {
        case .page(let token): "/s/\(token)"
        case .png(let token): "/s/\(token)/strip.png"
        case .gif(let token): "/s/\(token)/strip.gif"
        }
    }
}
