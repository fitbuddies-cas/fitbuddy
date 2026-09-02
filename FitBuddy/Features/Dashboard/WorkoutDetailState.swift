import Foundation

/// UI state of the workout detail screen (US-2 AC1, #98).
enum WorkoutDetailState: Equatable {
    /// The cache read has not finished yet.
    case loading
    /// The session was found, with its whole exercise tree.
    case loaded(WorkoutDetail)
    /// The session is not in the cache any more. A sync replaces the whole
    /// window, so it can vanish while this screen is open — the user deleted
    /// it in Hevy, or it aged out of the 90 days.
    case missing
    /// The cache could not be read. Kept apart from `.missing` for the reason
    /// `DashboardView` keeps `.failed` apart from `.empty`: "this session is
    /// gone" and "your data could not be read" are different statements, and
    /// only one of them is about the user's training.
    case failed
}
