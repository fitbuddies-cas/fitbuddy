import Foundation

/// One session's best estimated 1RM for a movement — a single point of the
/// progression curve (US-9 AC1, #41).
///
/// Per session, not per set: a session is what a user recognises as "the day I
/// benched", and plotting every set would turn the curve into the shape of the
/// warm-up ramp rather than of the progress. The best set of the day is the
/// one that says what the movement was capable of.
struct ProgressionPoint: Hashable, Identifiable, Sendable {
    /// Start of the session this point was taken from.
    let sessionStart: Date
    /// Epley estimate of the session's best set, in kg.
    let estimatedOneRepMaxKg: Double
    /// The set the estimate came from, so the detail screen can say *how* the
    /// number was reached — "102.5 kg" alone invites the question.
    let weightKg: Double
    let reps: Int

    /// Sessions are the identity here: a movement is folded to one point per
    /// session, so two points can never share a start.
    var id: Date { sessionStart }
}
