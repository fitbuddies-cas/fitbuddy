import Foundation

/// Formats how long a training session lasted, for the detail screen's header
/// (#98) and for the endurance figures of the cross-source analysis (US-15,
/// #181).
///
/// Hand-rolled in the same spirit as `SyncTimeFormatter`: the app's text is
/// English by policy, and a session is read in hours and minutes rather than
/// in the locale-negotiated forms a `DateComponentsFormatter` produces.
///
/// Moved from `Features/Dashboard/` with #181: a duration is no longer the
/// detail header's alone — the endurance sections read a moving time and a
/// weekly total through the same rule.
enum WorkoutDurationFormatter {
    /// `"52 min"`, `"1 h 12 min"`, `"2 h"`, `"< 1 min"`.
    ///
    /// `nil` when Hevy never closed the session, or when the end lies before
    /// the start (a clock change, a corrupted row): the header then shows no
    /// duration at all, which is the honest rendering of "we do not know".
    static func session(from start: Date, to end: Date?) -> String? {
        guard let end else { return nil }
        return seconds(end.timeIntervalSince(start))
    }

    /// The same form from a plain duration: `6_120` → `"1 h 42 min"`,
    /// `3_120` → `"52 min"`, `7_200` → `"2 h"`, `30` → `"< 1 min"`.
    ///
    /// What a connector delivers for an endurance activity is an elapsed or
    /// moving time in seconds rather than a pair of dates, and a weekly total
    /// is a sum of those — both read their duration through here.
    ///
    /// Hours are not rolled into days: a weekly endurance total of `"11 h"` is
    /// a figure the analysis prints, and `"0 d 11 h"` would help nobody.
    ///
    /// `nil` for a zero or negative duration. The output carries no grouping
    /// separator and no decimal mark, so it is already the locale-free form
    /// the prompt needs — there is no second variant of it.
    static func seconds(_ seconds: TimeInterval) -> String? {
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
