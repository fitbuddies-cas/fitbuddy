import Foundation

/// Classification of a logged set, as reported by Hevy's `set.type` field.
///
/// `ExerciseSet` stores the raw string rather than this enum: a value Hevy adds
/// later then decodes to `.unknown` instead of failing the whole sync, and the
/// stored column stays a plain `String` that `#Predicate` can filter on.
enum SetType: String, CaseIterable, Sendable {
    case normal
    case warmup
    case dropset
    case failure
    /// Any value this version does not know (including a missing type).
    case unknown

    /// Maps a raw Hevy value, falling back to `.unknown`.
    static func from(_ raw: String?) -> SetType {
        guard let raw else { return .unknown }
        return SetType(rawValue: raw.lowercased()) ?? .unknown
    }

    /// Whether the set counts towards training volume. Warm-up sets are
    /// excluded — they distort volume trends the dashboard (#26) reports on.
    var countsTowardsVolume: Bool {
        switch self {
        case .normal, .dropset, .failure:
            return true
        case .warmup, .unknown:
            return false
        }
    }
}
