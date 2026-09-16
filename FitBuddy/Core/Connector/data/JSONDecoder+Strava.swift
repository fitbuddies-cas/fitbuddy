import Foundation

extension JSONDecoder {
    /// Decoder configured for Strava's REST payloads.
    ///
    /// Strava sends timestamps as plain ISO 8601 in UTC (`2018-02-16T14:52:54Z`)
    /// and has not been observed to add fractional seconds. The Hevy decoder's
    /// two-formatter fallback is reused anyway: a millisecond that Strava
    /// starts sending one day is not worth failing a sync over.
    static var strava: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.hevyPlain.date(from: raw)
                    ?? ISO8601DateFormatter.hevyFractional.date(from: raw) else {
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
