import Foundation

/// The recovery figures of the last seven days, computed by the app and never
/// taken from the model (US-3 AC6, US-14 AC4, US-15 AC3, #175, #184).
///
/// Decides whether the recovery hint is mandatory, and is what the recovery
/// card shows: sessions, training days, mean RPE, mean heart rate and the
/// suggested rest. `Codable` so a validated report can be persisted as it was
/// shown (#176).
///
/// Since #184 the figures span **every** source and both domains: a week of
/// four bench sessions and three runs is seven days of training, not four.
/// Strength and endurance draw on the same recovery, which is what US-15 AC3
/// states and what the system prompt's rule 9 already tells the model.
///
/// The individual figures stay data-dependent (US-15 AC7): a mean nobody
/// recorded is `nil` and its cell is left out, never shown as `0` or `"—"`.
struct RecoveryMetrics: Codable, Equatable, Sendable {
    /// Training days within the last seven at which recovery comes before any
    /// progression (US-3 AC6).
    static let recoveryTrainingDays = 6

    /// Sessions in the last seven days, strength and endurance together.
    let sessions: Int
    /// Calendar days in the last seven carrying at least one session of any
    /// domain. Two sessions on one day — a morning run and an evening squat
    /// session included — are one training day.
    let trainingDays: Int
    /// Mean RPE over the counted **strength** sets that logged one, or `nil`
    /// when none did — Hevy sets carry no RPE unless the user enters it, and a
    /// placeholder would read as a measurement.
    ///
    /// Deliberately strength-only across the split. Strava's Relative Effort
    /// (`CardioMetrics.relativeEffort`) is a provider-specific, heart-rate-based
    /// score, not a 1–10 RPE, and averaging the two into one number would
    /// invent a measurement neither source made. Where the analysis reads it
    /// (#245, #246), it stands on its own as a trend within Strava
    /// (ADR-015, #242) — never averaged with RPE.
    let averageRPE: Double?
    /// Mean heart rate in bpm over the sessions of the week that recorded one,
    /// or `nil` when none did — a strength session has no strap, and an indoor
    /// session may have none either.
    ///
    /// Over *every* session that recorded one, not only the endurance ones: a
    /// Polar strength session carries a heart rate too, and the card says
    /// "Avg HR", not "average endurance heart rate". One session contributes
    /// one value; the mean is not weighted by duration, because duration is
    /// itself a figure a session may not have recorded. A recorded `0` is not
    /// a measurement — see `meanHeartRate(in:)`.
    ///
    /// Not the same figure as the prompt's "Mean heart rate", which is the
    /// endurance mean over the whole analysed window. The prompt's "Last 7
    /// days" line carries *this* one as well, so a card reason and the label
    /// under it always quote the same number.
    ///
    /// Decoded with `decodeIfPresent`, as Swift synthesises it for an optional,
    /// so a report persisted before #184 reads back without a heart rate
    /// instead of failing to decode.
    let averageHeartRate: Int?
    /// The rest the card suggests, from `suggestedRestHours(trainingDays:)`.
    /// Stored rather than derived, so a persisted card keeps the figure it was
    /// shown with even if the rule changes.
    let suggestedRestHours: Int

    /// Whether the last seven days reach the US-3 AC6 threshold.
    var needsRecovery: Bool { trainingDays >= Self.recoveryTrainingDays }

    init(sessions: Int, trainingDays: Int, averageRPE: Double?, averageHeartRate: Int? = nil) {
        self.sessions = sessions
        self.trainingDays = trainingDays
        self.averageRPE = averageRPE
        self.averageHeartRate = averageHeartRate
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
    /// A cardio day counts exactly as a strength day does, and #184 left the
    /// three figures themselves untouched. The rule measures days *without*
    /// rest, and FitBuddy records no intensity it could rank a run against a
    /// squat session by — weighting one below the other would be a judgement
    /// on data nobody collected. What the rule gained is reach: six days of
    /// running now produce 48 h where they used to produce 24 h.
    static func suggestedRestHours(trainingDays: Int) -> Int {
        switch trainingDays {
        case 7...: return 72
        case recoveryTrainingDays: return 48
        default: return 24
        }
    }
}

extension RecoveryMetrics {
    /// The sessions of the last seven days: the reference day and the six
    /// before it, the same span as the prompt's most recent week.
    ///
    /// Public to the feature so a caller knows which workouts the figures are
    /// built over.
    ///
    /// Every source and both domains since #184 — this is the set US-3 AC6 is
    /// counted over. For the subset the mean RPE is read from, see
    /// `lastSevenDaysStrengthSessions(in:now:calendar:)`.
    static func lastSevenDaysSessions(
        in summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        let start = AnalysisWindow.weekStart(0, endingAt: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return summaries.filter { $0.startTime >= start && $0.startTime < end }
    }

    /// The strength sessions of that week — the only ones that can carry an
    /// RPE, and therefore the only workouts a caller has to read the details
    /// of (#184).
    ///
    /// "Strength" is the normalized sport since #183, not the source: a Strava
    /// `WeightTraining` session is a strength session here, and a Hevy
    /// treadmill session is not.
    static func lastSevenDaysStrengthSessions(
        in summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        AnalysisPromptBuilder.sessions(
            in: lastSevenDaysSessions(in: summaries, now: now, calendar: calendar),
            for: .strength
        )
    }

    /// Builds the metrics from the cache.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order; anything outside the last
    ///     seven days is ignored. Endurance sessions count towards the
    ///     sessions, the training days and the mean heart rate (#184).
    ///   - details: The full workouts, for the RPE. Only those of the sessions
    ///     `lastSevenDaysStrengthSessions(in:now:calendar:)` returns count;
    ///     passing more changes nothing.
    ///   - now: The day the seven days end on.
    ///   - calendar: Decides where a day starts.
    init(
        summaries: [WorkoutSummary],
        details: [WorkoutDetail],
        now: Date,
        calendar: Calendar = .current
    ) {
        let sessions = Self.lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
        let strengthIDs = Set(AnalysisPromptBuilder.sessions(in: sessions, for: .strength).map(\.id))
        // Warm-ups excluded, as everywhere else: their RPE says nothing about
        // how hard the training was.
        let rpes = details
            .filter { strengthIDs.contains($0.id) }
            .flatMap(\.exercises)
            .flatMap(\.sets)
            .filter(\.countsTowardsVolume)
            .compactMap(\.rpe)
        self.init(
            sessions: sessions.count,
            trainingDays: Set(sessions.map { calendar.startOfDay(for: $0.startTime) }).count,
            averageRPE: rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count),
            averageHeartRate: Self.meanHeartRate(in: sessions)
        )
    }

    /// The mean of the average heart rates `summaries` recorded, or `nil` when
    /// none did.
    ///
    /// The rule the card's "Avg HR" and the prompt's "Last 7 days" line both
    /// read, so the figure a recovery reason cites and the figure printed under
    /// the label cannot be two different numbers (#184).
    ///
    /// A zero is discarded rather than averaged in: a provider that writes `0`
    /// for a session recorded without a strap is saying "not measured", and one
    /// run at 150 bpm next to such a row would otherwise read as 75 bpm. Same
    /// guard as `EndurancePromptSection`.
    static func meanHeartRate(in summaries: [WorkoutSummary]) -> Int? {
        let recorded = summaries.compactMap { $0.cardio?.averageHeartRate }.filter { $0 > 0 }
        guard !recorded.isEmpty else { return nil }
        return Int((Double(recorded.reduce(0, +)) / Double(recorded.count)).rounded())
    }
}
