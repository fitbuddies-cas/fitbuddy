import Foundation

/// The recovery figures of the last seven days, computed by the app and never
/// taken from the model (US-3 AC6, US-14 AC4, #175).
///
/// Decides whether the recovery hint is mandatory, and is what the recovery
/// card shows: sessions, training days, mean RPE and the suggested rest.
/// `Codable` so a validated report can be persisted as it was shown (#176).
struct RecoveryMetrics: Codable, Equatable, Sendable {
    /// Training days within the last seven at which recovery comes before any
    /// progression (US-3 AC6).
    static let recoveryTrainingDays = 6

    /// Strength sessions in the last seven days.
    let sessions: Int
    /// Calendar days in the last seven carrying at least one strength session.
    /// Two sessions on one day are one training day.
    let trainingDays: Int
    /// Mean RPE over the counted sets that logged one, or `nil` when none did —
    /// Hevy sets carry no RPE unless the user enters it, and a placeholder
    /// would read as a measurement.
    let averageRPE: Double?
    /// The rest the card suggests, from `suggestedRestHours(trainingDays:)`.
    /// Stored rather than derived, so a persisted card keeps the figure it was
    /// shown with even if the rule changes.
    let suggestedRestHours: Int

    /// Whether the last seven days reach the US-3 AC6 threshold.
    var needsRecovery: Bool { trainingDays >= Self.recoveryTrainingDays }

    init(sessions: Int, trainingDays: Int, averageRPE: Double?) {
        self.sessions = sessions
        self.trainingDays = trainingDays
        self.averageRPE = averageRPE
        self.suggestedRestHours = Self.suggestedRestHours(trainingDays: trainingDays)
    }

    /// The app's rest rule. No such rule existed before #175, so it is kept
    /// deliberately small and deterministic, and the model's
    /// `suggestedRestHours` is ignored:
    ///
    /// - 7 of 7 days: 72 h — no rest day at all, three to catch up.
    /// - 6 of 7 days (the US-3 AC6 threshold): 48 h — two rest days, the
    ///   figure of the design mock.
    /// - fewer: 24 h — one rest day. Keeps the rule total; no recovery card is
    ///   shown below the threshold (#175).
    ///
    /// Only strength sessions count (US-14 is strength-only); counting
    /// endurance sessions across sources is US-15 (#184).
    static func suggestedRestHours(trainingDays: Int) -> Int {
        switch trainingDays {
        case 7...: return 72
        case recoveryTrainingDays: return 48
        default: return 24
        }
    }
}

extension RecoveryMetrics {
    /// The strength sessions of the last seven days: the reference day and the
    /// six before it, the same span as the prompt's most recent week.
    ///
    /// Public to the feature so a caller knows which workouts to read the sets
    /// of before building the metrics.
    ///
    /// "Strength" is the normalized sport since #183, not the source: a Strava
    /// `WeightTraining` session is a strength session here, and a Hevy
    /// treadmill session is not. Counting endurance sessions towards the
    /// recovery figures is #184's scope, not this change's.
    static func lastSevenDaysSessions(
        in summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        let start = AnalysisWindow.weekStart(0, endingAt: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return AnalysisPromptBuilder.sessions(in: summaries, for: .strength)
            .filter { $0.startTime >= start && $0.startTime < end }
    }

    /// Builds the metrics from the cache.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order; anything outside the last
    ///     seven days, and every endurance session, is ignored.
    ///   - details: The full workouts, for the RPE. Only those of the sessions
    ///     `lastSevenDaysSessions(in:now:calendar:)` returns count; passing
    ///     more changes nothing.
    ///   - now: The day the seven days end on.
    ///   - calendar: Decides where a day starts.
    init(
        summaries: [WorkoutSummary],
        details: [WorkoutDetail],
        now: Date,
        calendar: Calendar = .current
    ) {
        let sessions = Self.lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
        let ids = Set(sessions.map(\.id))
        // Warm-ups excluded, as everywhere else: their RPE says nothing about
        // how hard the training was.
        let rpes = details
            .filter { ids.contains($0.id) }
            .flatMap(\.exercises)
            .flatMap(\.sets)
            .filter(\.countsTowardsVolume)
            .compactMap(\.rpe)

        self.init(
            sessions: sessions.count,
            trainingDays: Set(sessions.map { calendar.startOfDay(for: $0.startTime) }).count,
            averageRPE: rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
        )
    }
}
