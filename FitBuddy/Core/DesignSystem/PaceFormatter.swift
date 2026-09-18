import Foundation

/// Formats a running pace from the speed the connectors deliver (US-15, #181).
///
/// Strava and Polar report an average speed in metres per second; a runner
/// reads minutes per kilometre. The conversion and the clock form live here so
/// the cards, the session header and the prompt cannot disagree about the
/// figure.
enum PaceFormatter {
    /// The slowest pace still worth printing, in seconds per kilometre.
    ///
    /// A GPS track that drifted while the watch sat on a bench yields a speed
    /// near zero and a pace of hours per kilometre — a number, but not one
    /// anybody ran.
    private static let slowestSecondsPerKilometer = 99 * 60 + 59

    /// `3.2` m/s → `"5:12 /km"`, `2.5` → `"6:40 /km"`.
    ///
    /// The clock form rather than `"5.2 min/km"`, like
    /// `SetMetricFormatter.duration`: a pace is read off a watch, and the form
    /// carries no locale-negotiated separator, so it is written the same way
    /// on every device. No `locale` parameter for that reason, unlike
    /// `DistanceFormatter` and `HeartRateFormatter`: there is no digit here a
    /// locale could move.
    ///
    /// `nil` at zero or a negative speed, for a value that is not a finite
    /// number, and for a pace slower than
    /// `slowestSecondsPerKilometer`: a session without a usable pace shows no
    /// pace, which is a different statement from a pace of `0:00`.
    static func perKilometer(metersPerSecond: Double) -> String? {
        guard let clock = clock(metersPerSecond: metersPerSecond) else { return nil }
        return clock + " /km"
    }

    /// The same pace as data rather than as display text: `"5:12 min/km"`.
    ///
    /// The unit is spelled out where the UI abbreviates it — the prompt has no
    /// column header to lean on, and `/km` alone would leave the model to
    /// guess whether the figure counts minutes or seconds.
    static func plain(metersPerSecond: Double) -> String? {
        guard let clock = clock(metersPerSecond: metersPerSecond) else { return nil }
        return clock + " min/km"
    }

    /// `"5:12"` — minutes and seconds per kilometre, seconds always padded.
    private static func clock(metersPerSecond: Double) -> String? {
        guard metersPerSecond > 0, metersPerSecond.isFinite else { return nil }
        let secondsPerKilometer = Int((1_000 / metersPerSecond).rounded())
        guard secondsPerKilometer > 0, secondsPerKilometer <= slowestSecondsPerKilometer else {
            return nil
        }
        return String(format: "%d:%02d", secondsPerKilometer / 60, secondsPerKilometer % 60)
    }
}
