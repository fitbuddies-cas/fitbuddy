import Foundation

/// The two kinds of training an analysis judges separately (US-15, #182).
///
/// Strength and endurance are not one data basis with two labels: four bench
/// sessions and four runs are eight sessions in total and still too thin to
/// say anything firm about either discipline. Splitting them is what lets the
/// thin-data warning of US-6 AC2 name *which* half is thin instead of going
/// quiet because the total looks healthy (US-15 AC4).
///
/// Two cases on purpose, not three: "overall load" is a *profile* — a way of
/// looking at both domains at once — and belongs to #185, not here. A domain
/// is a property of the sessions; a profile is a choice the user makes about
/// them.
enum AnalysisDomain: String, CaseIterable, Sendable {
    case strength
    case endurance

    /// Mid-sentence form: the warning reads "Thin strength data — 3 sessions",
    /// so the word is lower case and never starts a line on its own.
    var displayName: String { rawValue }

    /// Which domain a session belongs to.
    ///
    /// `kind.isEndurance` and not `isCardio`: since #180 made `isCardio` a
    /// presentation rule, a Strava `WeightTraining` session that logged only
    /// a duration reads as cardio on the dashboard row while its `kind` is
    /// still `.strength` — and the domain is about what was trained, not
    /// about how the row is best displayed (ADR-012). Reading the source
    /// instead would file that session, and a Hevy session of treadmill
    /// sets, in the wrong half and warn about the wrong one.
    ///
    /// `.other` is a session whose sport was never recorded — a row cached
    /// before V5 — so the source is all that is left to go on.
    init(summary: WorkoutSummary) {
        if summary.kind == .other {
            self.init(source: summary.source)
        } else {
            self = summary.kind.isEndurance ? .endurance : .strength
        }
    }

    /// Which domain a source's sessions belong to, where nothing finer is
    /// recorded.
    ///
    /// The reading of a stored row from before #182, which counted sessions
    /// per source and nothing else, and of a fixture built the same way. It is
    /// what those runs meant: before ADR-012 the analysis split on the source
    /// and on nothing else.
    init(source: ConnectorSource) {
        self = source.isEnduranceSource ? .endurance : .strength
    }
}
