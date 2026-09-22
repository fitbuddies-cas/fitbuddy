import Foundation

/// The cache reads one analysis run built its prompt from (#178).
///
/// Kept past the prompt so the report that comes back is validated against
/// one snapshot of the cache (`AnalysisReportEvidence`, #175) — the data the
/// model was shown, read before the call — not against a second read the
/// cache may have changed under while the provider was answering.
struct AnalysisRunReads: Sendable {
    /// The sessions of the wide read, both domains (#183). The sections and
    /// the validation select what they need from them by `AnalysisDomain`.
    let summaries: [WorkoutSummary]
    /// The movements of the resolved window.
    let exercises: [ExerciseSummary]
    /// The progressions of the movements the prompt lists, by movement id.
    let progressions: [String: ExerciseProgression]
    /// The full workouts of the last seven days, for the mean RPE of the
    /// recovery figures. `nil` when they are unavailable — no detail reader,
    /// a failed read, or a session missing — so the figures carry no RPE
    /// rather than a mean over part of the week. Not part of the prompt.
    let details: [WorkoutDetail]?
    /// The window the prompt describes.
    let window: AnalysisWindow
    /// The reference the prompt was built with.
    let now: Date
}
