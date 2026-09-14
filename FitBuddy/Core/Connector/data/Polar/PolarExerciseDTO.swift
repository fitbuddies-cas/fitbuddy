import Foundation

/// One training session as returned by Polar AccessLink `GET /v3/exercises`
/// (ADR-11).
///
/// Only `id` and `startTime` are decoded strictly — the id identifies the
/// session for de-duplication against the cache, the start time decides
/// whether it falls inside the requested window. Every metric is optional:
/// which ones Polar populates depends on the watch, the sport and whether a
/// chest strap was worn.
struct PolarExerciseDTO: Decodable, Equatable, Sendable {
    let id: String
    /// Local wall-clock start, no zone (`2008-10-13T10:40:02`).
    let startTime: String
    /// Offset of `startTime` from UTC, in minutes.
    let startTimeUTCOffsetMinutes: Int?
    /// ISO-8601 duration (`PT2H44M`).
    let duration: String?
    let distanceMeters: Double?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let calories: Int?
    let trainingLoad: Double?
    let sport: String?
    let detailedSportInfo: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start-time"
        case startTimeUTCOffsetMinutes = "start-time-utc-offset"
        case duration
        case distance
        case heartRate = "heart-rate"
        case calories
        case trainingLoad = "training-load"
        case sport
        case detailedSportInfo = "detailed-sport-info"
    }

    private enum HeartRateKeys: String, CodingKey {
        case average
        case maximum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startTime = try container.decode(String.self, forKey: .startTime)
        startTimeUTCOffsetMinutes = try container.decodeIfPresent(Int.self, forKey: .startTimeUTCOffsetMinutes)
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distance)
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        trainingLoad = try container.decodeIfPresent(Double.self, forKey: .trainingLoad)
        sport = try container.decodeIfPresent(String.self, forKey: .sport)
        detailedSportInfo = try container.decodeIfPresent(String.self, forKey: .detailedSportInfo)

        if let hr = try? container.nestedContainer(keyedBy: HeartRateKeys.self, forKey: .heartRate) {
            averageHeartRate = try hr.decodeIfPresent(Int.self, forKey: .average)
            maximumHeartRate = try hr.decodeIfPresent(Int.self, forKey: .maximum)
        } else {
            averageHeartRate = nil
            maximumHeartRate = nil
        }
    }

    /// Maps to the normalized `Activity` (ADR-6). Returns `nil` when the start
    /// time cannot be parsed — an activity with no reliable timestamp cannot be
    /// placed in the training window and would corrupt every trend it feeds.
    func makeActivity() -> Activity? {
        guard let start = resolvedStartTime() else { return nil }
        let seconds = duration.flatMap(PolarDuration.seconds(from:))

        let metrics = ActivityMetrics(
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            activeCalories: calories,
            distanceMeters: distanceMeters,
            durationSeconds: seconds.map(Int.init),
            trainingLoad: trainingLoad,
            sport: detailedSportInfo ?? sport
        )

        // TODO(#5): once PR #152 (Strava) lands `Activity.source`, pass
        // `source: .polar` here explicitly — the default is `.hevy`, which
        // would silently mislabel every Polar activity.
        return Activity(
            id: "polar-\(id)",
            title: Self.title(sport: sport, detailed: detailedSportInfo),
            startTime: start,
            endTime: seconds.map { start.addingTimeInterval($0) },
            exercises: [],
            metrics: metrics.isEmpty ? nil : metrics
        )
    }

    /// Combines the zone-less `start-time` with `start-time-utc-offset`. Falls
    /// back to treating the value as UTC when the offset is missing.
    private func resolvedStartTime() -> Date? {
        guard let local = PolarDate.localFormatter.date(from: startTime) else { return nil }
        guard let offsetMinutes = startTimeUTCOffsetMinutes else { return local }
        return local.addingTimeInterval(TimeInterval(-offsetMinutes * 60))
    }

    /// A readable session title from Polar's sport labels — `RUNNING` →
    /// `Running`, preferring the more specific `detailed-sport-info`.
    static func title(sport: String?, detailed: String?) -> String {
        let raw = detailed ?? sport ?? "Workout"
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

/// Parser for the ISO-8601 duration form Polar uses (`PT2H44M30S`). Only the
/// time component (`T…`) ever appears for an exercise, so the date part
/// (`P…Y…M…D`) is intentionally not handled.
enum PolarDuration {
    static func seconds(from iso: String) -> TimeInterval? {
        guard iso.hasPrefix("PT") else { return nil }
        var total: TimeInterval = 0
        var number = ""
        var sawComponent = false

        for character in iso.dropFirst(2) {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let magnitude = Double(number) else { return nil }
            switch character {
            case "H": total += magnitude * 3600
            case "M": total += magnitude * 60
            case "S": total += magnitude
            default: return nil
            }
            sawComponent = true
            number = ""
        }
        // A trailing `number` means a magnitude with no unit — malformed.
        return sawComponent && number.isEmpty ? total : nil
    }
}

enum PolarDate {
    /// `2008-10-13T10:40:02` — local time, no zone, no fractional seconds.
    /// Fixed to `en_US_POSIX` / UTC so the parse is independent of the
    /// device locale and time zone; the real offset is applied separately.
    static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
