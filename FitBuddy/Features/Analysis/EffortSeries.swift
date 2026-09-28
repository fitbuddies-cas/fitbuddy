import Foundation

/// The values one effort scale recorded in the analysed window, by week
/// (US-18 AC4, #246) — what ADR-014 lists as "Anstrengung je Quelle: Werte pro
/// Quelle und Woche, nach Skala getrennt".
///
/// One series per scale, never one merged field (ADR-015 §1). The series
/// holds only what was recorded: a session without a value on this scale is
/// not in it, and a week without one has no entry — never a `0`, never a
/// default (ADR-014 §4). Whether the series is good enough to read, and which
/// way it points, is `AnalysisVerdictRule`'s call, not this type's.
struct EffortSeries: Equatable, Sendable {
    let scale: EffortScale
    /// Recorded values by week of the window, one per session. Week 0 is the
    /// last seven days (`AnalysisWindow.weekStart(0, …)`), week 1 the seven
    /// before, and so on. A week without any value is absent.
    let valuesByWeek: [Int: [Double]]

    /// Distinct weeks that carry at least one value.
    var weeksWithValues: Int {
        valuesByWeek.values.filter { !$0.isEmpty }.count
    }

    /// The mean over the last seven days, or `nil` when they carry no value.
    var lastSevenDaysMean: Double? {
        Self.mean(valuesByWeek[0] ?? [])
    }

    /// The mean over every value of the weeks before the last seven days, or
    /// `nil` when they carry none. A mean over sessions, within this one scale
    /// — the aggregation ADR-015 §1 allows.
    var precedingWeeksMean: Double? {
        Self.mean(valuesByWeek.filter { $0.key > 0 }.flatMap(\.value))
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

extension EffortSeries {
    /// One series per scale that recorded at least one value in the window,
    /// in `EffortScale.allCases` order. A scale with no value is absent.
    ///
    /// - Parameters:
    ///   - sessions: The sessions to read — the caller filters them to the
    ///     domains the profile covers. Sessions outside the window, or after
    ///     the reference day, are ignored.
    ///   - scales: The scales to build a series for.
    ///   - window: The window analysed; its weeks are the buckets.
    ///   - now: The reference the window ends on.
    ///   - calendar: Decides where a day starts.
    static func series(
        in sessions: [WorkoutSummary],
        scales: [EffortScale] = EffortScale.allCases,
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [EffortSeries] {
        let reference = calendar.startOfDay(for: now)
        let weekOf: (WorkoutSummary) -> Int? = { session in
            let day = calendar.startOfDay(for: session.startTime)
            guard let days = calendar.dateComponents([.day], from: day, to: reference).day,
                  days >= 0
            else { return nil }
            let week = days / 7
            return week < window.weeks ? week : nil
        }
        return scales.compactMap { scale in
            var valuesByWeek: [Int: [Double]] = [:]
            for session in sessions {
                guard let value = scale.value(of: session), let week = weekOf(session) else { continue }
                valuesByWeek[week, default: []].append(value)
            }
            return valuesByWeek.isEmpty ? nil : EffortSeries(scale: scale, valuesByWeek: valuesByWeek)
        }
    }
}
