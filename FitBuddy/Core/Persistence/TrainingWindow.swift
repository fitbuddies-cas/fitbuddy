import Foundation

/// The 90-day window US-2 defines for the dashboard.
///
/// Kept in one place so the cache read (#26) and the fetch (#25) cannot drift
/// apart on the window length or on where a day starts.
enum TrainingWindow {
    /// Window length in days (US-2).
    static let days = 90

    /// Window length in weeks, used to average training days per week.
    static var weeks: Double { Double(days) / 7 }

    /// Midnight, `days` days before `reference` — day-aligned so the window
    /// does not drift with the time of day the dashboard happens to open.
    static func start(endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -days, to: midnight) ?? midnight
    }
}
