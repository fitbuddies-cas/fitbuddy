import Foundation

/// The windows the AI analysis reasons over (US-3, #30).
///
/// Four weeks, not the dashboard's 90 days: a recommendation for the next
/// training block follows from recent training, and a lifter's shape three
/// months ago mostly adds noise. The equally long preceding window is what
/// makes progression visible — without a second window the prompt could state
/// volume, but never whether it is rising or falling.
enum AnalysisWindow {
    /// Calendar days the recent window covers, including the reference day.
    static let days = 28
    /// Whole weeks in the window, used to average training days.
    static let weeks = Double(days) / 7

    /// Midnight, `days - 1` days before `reference`.
    ///
    /// Minus one because the reference day counts itself: 28 days back from
    /// midnight would span 29 days and quietly deflate every per-week average
    /// derived from it.
    static func start(endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -(days - 1), to: midnight) ?? midnight
    }

    /// Midnight `days` days before `start(endingAt:)` — the beginning of the
    /// comparison window, which ends where the recent one begins.
    static func previousStart(endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let recentStart = start(endingAt: reference, calendar: calendar)
        return calendar.date(byAdding: .day, value: -days, to: recentStart) ?? recentStart
    }

    /// Midnight of the first day of week `index`, counted back from
    /// `reference`: index 0 is the seven days ending on the reference day.
    static func weekStart(_ index: Int, endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -(7 * index + 6), to: midnight) ?? midnight
    }
}
