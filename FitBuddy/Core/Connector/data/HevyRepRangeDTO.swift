import Foundation

/// The `rep_range` object of a routine set inside `GET /v1/routines` — the
/// range a set is meant to land in (`8–12`), as opposed to the single `reps`
/// value a routine may carry instead.
///
/// Both ends are optional in Hevy's schema, and the object itself arrives as
/// `null` on a set that uses `reps` (which is what every routine observed on
/// the live API did).
struct HevyRepRangeDTO: Decodable, Equatable, Sendable {
    let start: Int?
    let end: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeLooseIntIfPresent(forKey: .start)
        end = try container.decodeLooseIntIfPresent(forKey: .end)
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
    }
}
