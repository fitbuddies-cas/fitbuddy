import Foundation

extension JSONDecoder {
    /// Decoder configured for Hevy's REST payloads.
    ///
    /// Hevy documents its timestamps as ISO 8601 (`2021-09-14T12:00:00Z`) but
    /// has been observed to include fractional seconds, which the standard
    /// `.iso8601` strategy rejects outright. Accepting both keeps a single
    /// millisecond-precision workout from failing the whole sync.
    static var hevy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.hevyFractional.date(from: raw)
                    ?? ISO8601DateFormatter.hevyPlain.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an ISO 8601 timestamp: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    /// `2021-09-14T12:00:00.123Z`
    static let hevyFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `2021-09-14T12:00:00Z`
    static let hevyPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
