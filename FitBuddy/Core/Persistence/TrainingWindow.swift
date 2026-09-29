import Foundation

/// The dashboard window US-2 defines, shared by the fetch (`WorkoutSyncService`) and
/// the cache read (`WorkoutStore+Summaries`) so the two cannot drift apart on
/// the window length or on where a day starts.
enum TrainingWindow {
    /// Offset of the window's first midnight from the reference day (US-2).
    static let days = 90

    /// Calendar days the window actually covers.
    ///
    /// One more than `days`: the boundary is midnight `days` days back and the
    /// reference day itself is included, so both ends count. Ignoring this is
    /// what let the average exceed 7 training days per week.
    static var spanDays: Int { days + 1 }

    /// Window length in weeks (exactly 13), used to average training days.
    static var weeks: Double { Double(spanDays) / 7 }

    /// Number of whole-week buckets the window splits into (13), oldest first,
    /// for the weekly volume trend on the dashboard.
    static var weekCount: Int { (spanDays + 6) / 7 }

    /// Midnight, `days` days before `reference` — day-aligned so the window
    /// does not drift with the time of day the user happens to sync or open
    /// the dashboard.
    static func start(endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -days, to: midnight) ?? midnight
    }
}
