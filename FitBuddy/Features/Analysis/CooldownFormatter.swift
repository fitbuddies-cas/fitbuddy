import Foundation

/// Formats the remaining 6h analysis cooldown (US-3, NFR «Next analysis
/// available in Xh Ym»).
///
/// Hand-rolled for the same reason as `SyncTimeFormatter`: the wording is
/// fixed by the requirement, and the output is English by policy, so there is
/// no locale to negotiate.
enum CooldownFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600

    /// `"5h 12m"`, `"12m"`, `"1m"`. `nil` once the cooldown has elapsed, so
    /// the caller drops the label instead of showing "0m".
    ///
    /// Rounded up, never down: with 90 seconds left, "1m" would invite a tap
    /// that is still refused, and a countdown that hits "0m" while the button
    /// stays disabled reads as a broken screen.
    static func remaining(until availableAt: Date, now: Date) -> String? {
        let seconds = availableAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let minutes = Int((seconds / minute).rounded(.up))
        let hours = minutes / 60
        let restMinutes = minutes % 60
        return hours > 0 ? "\(hours)h \(restMinutes)m" : "\(restMinutes)m"
    }

    /// The full line under the analysis button: `"Next analysis available in
    /// 5h 12m"`, or `nil` when an analysis may run now.
    static func message(until availableAt: Date?, now: Date) -> String? {
        guard let availableAt, let remaining = remaining(until: availableAt, now: now) else { return nil }
        return "Next analysis available in \(remaining)"
    }
}
