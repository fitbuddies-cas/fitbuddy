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
    /// `trainingDayCount` spread over the window's ~12.9 weeks.
    let averageTrainingDaysPerWeek: Double

    /// Aggregates the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Workouts inside the window, in any order.
    ///   - calendar: Decides where a day starts, so the training-day count
    ///     follows the user's time zone.
    init(summaries: [WorkoutSummary], calendar: Calendar = .current) {
        let trainingDays = Set(summaries.map { calendar.startOfDay(for: $0.startTime) })

        totalVolumeKg = summaries.reduce(0) { $0 + $1.volumeKg }
        workoutCount = summaries.count
        trainingDayCount = trainingDays.count
        // Divided by the full window, not by the span between the first and
        // last workout: three sessions in one week after a two-month break are
        // not "3 days/week" — the average has to show the gap.
        averageTrainingDaysPerWeek = Double(trainingDays.count) / TrainingWindow.weeks
    }
}

extension DashboardMetrics {
    /// The all-zero state for an empty window.
    static let empty = DashboardMetrics(summaries: [])
}
