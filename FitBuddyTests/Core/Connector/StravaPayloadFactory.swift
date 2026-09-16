import Foundation

/// Builds Strava's wire format for tests that exercise `StravaConnector`'s
/// decoding — the counterpart to `HevyPayloadFactory`.
enum StravaPayloadFactory {
    /// One "SummaryActivity" as `GET /athlete/activities` lists it. Defaults
    /// describe a 5 km run in 30 minutes of moving time.
    static func activity(
        id: Int64,
        start: Date,
        name: String? = "Morning Run",
        sportType: String? = "Run",
        type: String? = "Run",
        distance: Double? = 5000,
        movingTime: Int? = 1800,
        elapsedTime: Int? = 1900
    ) -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "start_date": iso(start),
            "start_date_local": iso(start),
            "timezone": "(GMT+01:00) Europe/Zurich",
            "athlete": ["id": 42],
        ]
        if let name { json["name"] = name }
        if let sportType { json["sport_type"] = sportType }
        if let type { json["type"] = type }
        if let distance { json["distance"] = distance }
        if let movingTime { json["moving_time"] = movingTime }
        if let elapsedTime { json["elapsed_time"] = elapsedTime }
        return json
    }

    /// One page: Strava returns a bare JSON array.
    static func page(_ activities: [[String: Any]]) -> Data {
        // Test fixture: the dictionaries above are JSON-serializable by
        // construction.
        (try? JSONSerialization.data(withJSONObject: activities)) ?? Data()
    }

    /// `2018-02-16T14:52:54Z`
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
