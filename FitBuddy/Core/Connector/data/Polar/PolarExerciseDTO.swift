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
    /// Legacy load, reported by older devices as well.
    let trainingLoad: Double?
    /// `training_load_pro.cardio-load` — `nil` when the block is missing.
    let cardioLoad: Double?
    /// `training_load_pro.muscle-load`.
    let muscleLoad: Double?
    /// `training_load_pro.perceived-load`.
    let perceivedLoad: Double?
    /// `training_load_pro.user-rpe`.
    let userRPE: PolarUserRPE?
    let sport: String?
    let detailedSportInfo: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case startTimeUTCOffsetMinutes = "start_time_utc_offset"
        case duration
        case distance
        case heartRate = "heart_rate"
        case calories
        case trainingLoad = "training_load"
        case trainingLoadPro = "training_load_pro"
        case sport
        case detailedSportInfo = "detailed_sport_info"
    }

    private enum HeartRateKeys: String, CodingKey {
        case average
        case maximum
    }

    /// Keys inside `training_load_pro`. Polar writes these with **hyphens**
    /// while the exercise around them uses underscores — in the same
    /// response. The `*-interpretation` labels are not decoded: nothing reads
    /// them yet.
    private enum TrainingLoadProKeys: String, CodingKey {
        case cardioLoad = "cardio-load"
        case muscleLoad = "muscle-load"
        case perceivedLoad = "perceived-load"
        case userRPE = "user-rpe"
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

        // Training Load Pro is device-bound: an older watch sends no block at
        // all, and that is not an error — every value simply stays `nil`.
        // Each field is decoded tolerantly: the block is optional enrichment,
        // so a value of an unexpected type (or a block that is not an object)
        // drops that value only, never the session — and with it the whole
        // `[PolarExerciseDTO]` list the client decodes.
        if let pro = try? container.nestedContainer(keyedBy: TrainingLoadProKeys.self, forKey: .trainingLoadPro) {
            cardioLoad = try? pro.decodeIfPresent(Double.self, forKey: .cardioLoad)
            muscleLoad = try? pro.decodeIfPresent(Double.self, forKey: .muscleLoad)
            perceivedLoad = try? pro.decodeIfPresent(Double.self, forKey: .perceivedLoad)
            userRPE = try? pro.decodeIfPresent(PolarUserRPE.self, forKey: .userRPE)
        } else {
            cardioLoad = nil
            muscleLoad = nil
            perceivedLoad = nil
            userRPE = nil
        }
    }

    /// Maps to the normalized `Activity` (ADR-6). Returns `nil` when the start
    /// time cannot be parsed — an activity with no reliable timestamp cannot be
    /// placed in the training window and would corrupt every trend it feeds.
    func makeActivity() -> Activity? {
        guard let start = resolvedStartTime() else { return nil }
        let seconds = duration.flatMap(PolarDuration.seconds(from:))

        // Polar reports no sets, so distance and duration travel in the
        // cardio block rather than on an `ActivityExerciseSet`. Average speed
        // is derived here — Polar sends neither speed nor pace at session
        // level, and the pair it does send determines it.
        let cardio = CardioMetrics(
            averageHeartRate: averageHeartRate,
            maxHeartRate: maximumHeartRate,
            averageSpeedMetersPerSecond: Self.averageSpeed(meters: distanceMeters, seconds: seconds),
            activeCalories: calories,
            // Zero means "not logged" for both, as it does for average speed
            // above: an indoor session Polar never measured spatially sends
            // `distance: 0.0`, and "0 m" on the dashboard row would read as a
            // bug where the duration belongs.
            distanceMeters: distanceMeters.flatMap { $0 > 0 ? $0 : nil },
            durationSeconds: seconds.flatMap { $0 > 0 ? Int($0) : nil },
            trainingLoad: trainingLoad,
            cardioLoad: cardioLoad,
            muscleLoad: muscleLoad,
            perceivedLoad: perceivedLoad,
            userRPE: userRPE
        )

        return Activity(
            id: "polar-\(id)",
            title: Self.title(sport: sport, detailed: detailedSportInfo),
            startTime: start,
            endTime: seconds.map { start.addingTimeInterval($0) },
            source: .polar,
            kind: Self.kind(sport: sport, detailed: detailedSportInfo),
            exercises: [],
            cardio: cardio.nonEmpty
        )
    }

    /// Combines the zone-less `start_time` with `start_time_utc_offset`. Falls
    /// back to treating the value as UTC when the offset is missing.
    private func resolvedStartTime() -> Date? {
        guard let local = PolarDate.localFormatter.date(from: startTime) else { return nil }
        guard let offsetMinutes = startTimeUTCOffsetMinutes else { return local }
        return local.addingTimeInterval(TimeInterval(-offsetMinutes * 60))
    }

    /// Maps Polar's sport vocabulary onto `ActivityKind` — the only place it
    /// happens (#180).
    ///
    /// Both labels are consulted, the finer one first: `detailed_sport_info`
    /// is more specific than `sport`, but it is also the one Polar keeps
    /// extending, and an unrecognised `FUNCTIONAL_TRAINING` must not drop a
    /// session whose `sport` plainly says `STRENGTH_TRAINING` out of the
    /// strength domain. So `.other` from the detailed label means "ask the
    /// coarse one", not "unclassified".
    static func kind(sport: String?, detailed: String?) -> ActivityKind {
        let fromDetailed = kind(label: detailed)
        return fromDetailed == .other ? kind(label: sport) : fromDetailed
    }

    /// One Polar sport label.
    ///
    /// Matched on a substring of the upper-case label, because Polar composes
    /// its sports the other way round from Strava: the discipline sits at the
    /// end (`TREADMILL_RUNNING`, `OPEN_WATER_SWIMMING`) or the start
    /// (`RUNNING_INDOOR`). Anything else — `OTHER_INDOOR`, `YOGA` — is
    /// `.other`.
    private static func kind(label: String?) -> ActivityKind {
        let raw = (label ?? "").uppercased()
        if raw.contains("STRENGTH") { return .strength }
        if raw.contains("RUNNING") || raw.contains("JOGGING") { return .run }
        if raw.contains("CYCLING") || raw.contains("BIKING") { return .ride }
        if raw.contains("SWIMMING") { return .swim }
        if raw.contains("HIKING") { return .hike }
        if raw.contains("WALKING") { return .walk }
        return .other
    }

    /// Metres per second over the session, when Polar reported both figures.
    private static func averageSpeed(meters: Double?, seconds: TimeInterval?) -> Double? {
        guard let meters, let seconds, meters > 0, seconds > 0 else { return nil }
        return meters / seconds
    }

    /// A readable session title from Polar's sport labels — `RUNNING` →
    /// `Running`, preferring the more specific `detailed_sport_info`.
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
