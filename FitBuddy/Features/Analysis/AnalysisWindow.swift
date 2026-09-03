import Foundation

/// The window the AI analysis reasons over, plus the equally long window
/// before it (US-3, #30, widened in #87).
///
/// Four weeks is the default, not the dashboard's 90 days: a recommendation
/// for the next training block follows from recent training, and a lifter's
/// shape three months ago mostly adds noise. The equally long preceding window
/// is what makes progression visible — without a second window the prompt
/// could state volume, but never whether it is rising or falling.
///
/// The default is not a hard boundary though. Someone coming back from a
/// six-week break has training data worth analysing; blocking them because the
/// last four weeks happen to be empty turns the analysis button into a dead
/// end. `resolve(for:endingAt:calendar:)` therefore widens the window until it
/// finds training, and everything downstream — prompt headers, per-week rows,
/// the frequency average — reads its length from the resolved value rather
/// than from a constant.
struct AnalysisWindow: Equatable, Sendable {
    /// Whole weeks the window covers. Whole weeks because the prompt buckets
    /// the window into weekly rows, and a partial one would misreport volume.
    let weeks: Int

    /// Calendar days the window covers, including the reference day.
    var days: Int { weeks * 7 }

    init(weeks: Int) {
        self.weeks = weeks
    }

    /// The window every analysis starts from.
    static let `default` = AnalysisWindow(weeks: 4)

    /// The fallback ladder of #87, narrowest first: 4 → 8 → 13 weeks. The
    /// first rung holding a workout wins.
    ///
    /// It ends at 13 weeks because that is where the data ends — the cache
    /// keeps `TrainingWindow.spanDays` (91 days), so a wider rung could only
    /// ever repeat the previous one's verdict on the same sessions.
    static let ladder: [AnalysisWindow] = [.default, AnalysisWindow(weeks: 8), AnalysisWindow(weeks: 13)]

    /// The widest rung — the window a full cache is analysed over, and the
    /// boundary the dashboard's analysis button is gated on (#87).
    static var widest: AnalysisWindow { ladder[ladder.count - 1] }

    /// Whether this is the 4-week default. The UI only names the window when
    /// it is not (#87).
    var isDefault: Bool { self == .default }

    /// The narrowest rung of the ladder that holds at least one workout, or
    /// `nil` when none of them does — the one case that is genuinely "no
    /// training data" rather than "no *recent* training data".
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order.
    ///   - reference: The day the windows end on.
    static func resolve(
        for summaries: [WorkoutSummary],
        endingAt reference: Date,
        calendar: Calendar = .current
    ) -> AnalysisWindow? {
        ladder.first { window in
            let start = window.start(endingAt: reference, calendar: calendar)
            return summaries.contains { $0.startTime >= start }
        }
    }

    /// Midnight, `days - 1` days before `reference`.
    ///
    /// Minus one because the reference day counts itself: 28 days back from
    /// midnight would span 29 days and quietly deflate every per-week average
    /// derived from it.
    func start(endingAt reference: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -(days - 1), to: midnight) ?? midnight
    }

    /// Midnight `days` days before `start(endingAt:)` — the beginning of the
    /// comparison window, which ends where the recent one begins.
    ///
    /// For the wider rungs this reaches past the cache. That is intentional:
    /// the read simply returns what is there, and the prompt says plainly that
    /// an empty comparison window may be the start of the recorded history
    /// rather than a break.
    func previousStart(endingAt reference: Date, calendar: Calendar = .current) -> Date {
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
