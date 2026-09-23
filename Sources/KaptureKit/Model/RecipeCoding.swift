import Foundation

/// `JSONEncoder`'s stock `.iso8601` strategy truncates fractional seconds,
/// making a decoded recipe unequal to the one just saved — this keeps it exact.
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
