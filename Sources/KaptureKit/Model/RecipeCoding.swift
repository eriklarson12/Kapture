import Foundation

/// The one blessed JSON configuration for recipes and templates.
///
/// Recipes are written to disk and shared between users, so serialization is
/// part of the format, not a call-site choice. `JSONEncoder`'s stock `.iso8601`
/// strategy truncates fractional seconds, which makes a decoded recipe unequal
/// to the one just saved; these keep the timestamp exact while staying readable.
public enum RecipeCoding {
    static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, target in
            var container = target.singleValueContainer()
            try container.encode(formatter().string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { source in
            let text = try source.singleValueContainer().decode(String.self)
            guard let date = formatter().date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: source.codingPath,
                        debugDescription: "Expected an ISO 8601 date with fractional seconds, got \(text)."
                    )
                )
            }
            return date
        }
        return decoder
    }
}
