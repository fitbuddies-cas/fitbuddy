import Foundation

/// The cache reads one analysis run built its prompt from (#178).
///
/// Kept past the prompt so the report that comes back is validated against
/// exactly the data the model was shown (`AnalysisReportEvidence`, #175),
/// not against a second read the cache may have changed under in between.
struct AnalysisRunReads: Sendable {
    /// Strength sessions of the wide read.
    let summaries: [WorkoutSummary]
    /// The movements of the resolved window.
    let exercises: [ExerciseSummary]
    /// The progressions of the movements the prompt lists, by movement id.
    let progressions: [String: ExerciseProgression]
    /// The window the prompt describes.
    let window: AnalysisWindow
    /// The reference the prompt was built with.
    let now: Date
}
