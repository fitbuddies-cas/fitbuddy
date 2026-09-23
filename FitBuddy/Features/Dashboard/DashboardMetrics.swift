import Foundation

/// The aggregate figures the dashboard header shows for the 90-day window
/// (US-2 AC1): total training volume and average training days per week.
struct DashboardMetrics: Equatable, Sendable {
    /// Σ (weight × reps) over every counted set in the window, in kg.
    let totalVolumeKg: Double
    /// Number of workouts in the window.
    let workoutCount: Int
    /// Calendar days on which at least one workout took place. Two sessions on
    /// the same day are one training day.
    let trainingDayCount: Int
    /// `trainingDayCount` spread over the window's 13 weeks. Capped at 7 by
    /// construction: the divisor covers every day the window contains.
    let averageTrainingDaysPerWeek: Double
    /// Volume split by muscle group, heaviest first — the distribution chart
    /// on the dashboard (#27). Empty when no workout in the window loaded a
    /// group this version recognises.
    let muscleDistribution: [MuscleLoad]
    /// Strength volume per week of the window, oldest week first, always
    /// `TrainingWindow.weekCount` entries — a week without a session is a
    /// zero, not a gap, so the trend line keeps its time axis honest.
    let weeklyVolumesKg: [Double]

    /// Aggregates the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Workouts inside the window, in any order.
    ///   - calendar: Decides where a day starts, so the training-day count
    ///     follows the user's time zone.
    /// - Parameters:
    ///   - summaries: The sessions inside the window, in any order.
    ///   - reference: The day the window ends on — the same clock the
    ///     ViewModel used to query the cache, so the week buckets line up
    ///     with the window boundary rather than with the first session.
    init(summaries: [WorkoutSummary], endingAt reference: Date = Date(), calendar: Calendar = .current) {
        let trainingDays = Set(summaries.map { calendar.startOfDay(for: $0.startTime) })
        let windowStart = TrainingWindow.start(endingAt: reference, calendar: calendar)
        var weekly = Array(repeating: 0.0, count: TrainingWindow.weekCount)
        for summary in summaries {
            let day = calendar.startOfDay(for: summary.startTime)
            let offset = calendar.dateComponents([.day], from: windowStart, to: day).day ?? 0
            // Clamped rather than dropped: a session a few hours outside the
            // boundary still belongs to the nearest week, not to nowhere.
            let week = min(max(offset / 7, 0), weekly.count - 1)
            weekly[week] += summary.volumeKg
        }
        weeklyVolumesKg = weekly

        totalVolumeKg = summaries.reduce(0) { $0 + $1.volumeKg }
        muscleDistribution = MuscleLoad.merged(summaries.flatMap(\.muscleLoads))
        workoutCount = summaries.count
        trainingDayCount = trainingDays.count
        // Divided by the full window, not by the span between the first and
        // last workout: three sessions in one week after a two-month break are
        // not "3 days/week" — the average has to show the gap.
        averageTrainingDaysPerWeek = Double(trainingDays.count) / TrainingWindow.weeks
    }
}
