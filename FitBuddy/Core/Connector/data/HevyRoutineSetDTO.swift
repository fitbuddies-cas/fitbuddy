import Foundation

/// One prescribed set of a routine exercise inside `GET /v1/routines`.
///
/// The response schema types `type` as a plain string with a description,
/// not as an enum, so it is read through `SetType.from` with its `.unknown`
/// fallback — the same tolerance the logged sets get.
struct HevyRoutineSetDTO: Decodable, Equatable, Sendable {
    let type: String?
    let reps: Int?
    let repRange: HevyRepRangeDTO?

    // `weight_kg` is on the wire too, and deliberately not decoded: nothing
    // reads a prescribed weight (the 2-for-2 rule compares reps), and a
    // field nobody reads is a field nobody notices going wrong.
    private enum CodingKeys: String, CodingKey {
        case type
        case reps
        case repRange = "rep_range"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        reps = try container.decodeLooseIntIfPresent(forKey: .reps)
        repRange = try container.decodeIfPresent(HevyRepRangeDTO.self, forKey: .repRange)
    }

    /// Typed view of `type` — what the per-kind matching of
    /// `HevyRoutineExerciseDTO.targetReps(forSet:warmUp:)` reads.
    var setType: SetType {
        SetType.from(type)
    }

    /// The repetitions this set is meant to reach (#240, ADR-013): the top of
    /// the range, else its bottom, else the single value — else none.
    ///
    /// The top of the range because that is what the 2-for-2 rule compares
    /// against: exceeding the *bottom* of `8–12` by two reps is landing inside
    /// the range, not outgrowing it. `nil` is a valid outcome — a routine set
    /// without a rep target (a timed plank, a carry) prescribes nothing to
    /// beat.
    var targetReps: Int? {
        repRange?.end ?? repRange?.start ?? reps
    }
}
