import Foundation

/// Formats how long a training session lasted, for the detail screen's header
/// (#98).
///
/// Hand-rolled in the same spirit as `SyncTimeFormatter`: the app's text is
/// English by policy, and a session is read in hours and minutes rather than
/// in the locale-negotiated forms a `DateComponentsFormatter` produces.
enum WorkoutDurationFormatter {
    /// `"52 min"`, `"1 h 12 min"`, `"2 h"`, `"< 1 min"`.
    ///
    /// `nil` when Hevy never closed the session, or when the end lies before
    /// the start (a clock change, a corrupted row): the header then shows no
    /// duration at all, which is the honest rendering of "we do not know".
    static func session(from start: Date, to end: Date?) -> String? {
        guard let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return nil }

        let minutes = Int(seconds / 60)
        // A session Hevy closed within the same minute is real but shorter
        // than the unit — `"0 min"` would read as a session that never
        // happened.
        guard minutes > 0 else { return "< 1 min" }
        guard minutes >= 60 else { return "\(minutes) min" }

        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }
}
