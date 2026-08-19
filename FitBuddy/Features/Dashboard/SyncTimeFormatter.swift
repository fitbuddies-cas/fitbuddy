import Foundation

/// Formats the "last synced" timestamp the dashboard must always show
/// (US-2 AC2).
///
/// Hand-rolled rather than `RelativeDateTimeFormatter`, which would render an
/// hours-old sync as "1 hour ago" and hide the minutes — exactly the precision
/// the banner exists for. The output is English by policy, so no locale
/// negotiation is involved.
enum SyncTimeFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    /// `"just now"`, `"14 min ago"`, `"2 h 14 min ago"`, `"3 days ago"`.
    ///
    /// A timestamp in the future (clock change, restored backup) reads as
    /// "just now": negative ages are meaningless to the user and "in 4 hours"
    /// would look like a bug.
    static func relative(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))

        switch seconds {
        case ..<minute:
            return "just now"
        case ..<hour:
            return "\(Int(seconds / minute)) min ago"
        case ..<day:
            let hours = Int(seconds / hour)
            let minutes = Int(seconds.truncatingRemainder(dividingBy: hour) / minute)
            return minutes == 0 ? "\(hours) h ago" : "\(hours) h \(minutes) min ago"
        default:
            let days = Int(seconds / day)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    /// The full line above the dashboard: `"Last synced 14 min ago"`, or
    /// `"Never synced"` when no sync has ever completed.
    static func lastSynced(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never synced" }
        return "Last synced " + relative(since: date, now: now)
    }
}
