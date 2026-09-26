import Foundation

/// How strength and endurance sat in the same week — the figures behind the
/// interference card (US-15 AC2, #186).
///
/// Counted by the app over the last seven days and never taken from the model,
/// exactly as `RecoveryMetrics` is: the model is asked to say what to do about
/// the pattern, not what the pattern was. `Codable` so a validated report keeps
/// the figures it was shown with (#176).
///
/// The one thing neither domain section of the prompt can state on its own.
/// "Four strength days" and "four running days" are compatible with a week of
/// eight sessions on eight days and with a week of four doubles, and the two
/// weeks call for opposite advice.
struct InterferenceMetrics: Codable, Equatable, Sendable {
    /// The window the counts are made over. Seven days, the same week
    /// `RecoveryMetrics` judges, so a report cannot cite two different weeks.
    static let defaultDays = 7

    /// Calendar days of the window carrying at least one strength session.
    let strengthDays: Int
    /// Calendar days carrying at least one endurance session.
    let cardioDays: Int
    /// Calendar days carrying both. Never larger than either count — the
    /// intersection of two day sets.
    let overlapDays: Int
    /// The window, in days. Stored rather than derived, so a persisted card
    /// keeps the week it was written for even if the rule changes.
    let days: Int

    init(strengthDays: Int, cardioDays: Int, overlapDays: Int, days: Int = defaultDays) {
        self.strengthDays = strengthDays
        self.cardioDays = cardioDays
        self.overlapDays = overlapDays
        self.days = days
    }

    /// Whether the week actually holds both domains — the condition an
    /// interference card is validated against.
    ///
    /// A week of lifting alone has no interference to talk about, whatever the
    /// model wrote, and a card built over it would state two counts and a zero
    /// as if they were a finding.
    var hasBothDomains: Bool { strengthDays > 0 && cardioDays > 0 }

    /// The counts over the last seven days of `summaries`, across every
    /// source.
    ///
    /// The domain of a session is `AnalysisDomain(summary:)` — the sport,
    /// since ADR-012 — so a Strava `WeightTraining` session counts as a
    /// strength day and a Hevy treadmill session as a cardio one. Two sessions
    /// on one day are one day, which is the whole point of counting days
    /// rather than sessions here.
    static func metrics(
        in summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> InterferenceMetrics {
        let week = RecoveryMetrics.lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
        let strength = week.filter { AnalysisDomain(summary: $0) == .strength }
        let endurance = week.filter { AnalysisDomain(summary: $0) == .endurance }
        let strengthDays = PromptFigures.trainingDayStarts(strength, calendar: calendar)
        let cardioDays = PromptFigures.trainingDayStarts(endurance, calendar: calendar)
        return InterferenceMetrics(
            strengthDays: strengthDays.count,
            cardioDays: cardioDays.count,
            overlapDays: strengthDays.intersection(cardioDays).count,
            days: defaultDays
        )
    }
}
