import Foundation

/// How current a data source's cached data is, judged from the timestamp of its
/// last successful sync (US-8 AC1).
///
/// Separate from `SyncStatus`, which reports the last sync *attempt*. The two
/// answer different questions and can disagree in the way that matters most: a
/// source sitting at `.idle` — nothing failed, nothing running — can still be
/// three days out of date because nobody opened the app. That silence is
/// exactly what US-8 exists to break, and only a freshness judgement catches
/// it.
enum DataSourceFreshness: Equatable {
    /// No sync ever completed for this source.
    case never
    /// The last successful sync is within `staleThreshold`.
    case fresh
    /// The last successful sync is older than `staleThreshold`.
    ///
    /// Carries no date: the timestamp is `DataSourceStatus.lastSync`, which
    /// every caller already holds and which `SyncTimeFormatter` renders for
    /// all three cases at once — a payload here would only be a second copy
    /// of it, and it was read by nothing but the tests (#40 review).
    case stale

    /// How old a sync may get before the dashboard flags it (US-8 AC1: 24 h).
    static let staleThreshold: TimeInterval = 86_400

    /// Judges `lastSync` against the clock.
    ///
    /// - Parameters:
    ///   - lastSync: Last successful sync, or `nil` if none ever completed.
    ///   - now: The instant to judge against — injected so the tests do not
    ///     have to wait a day.
    init(lastSync: Date?, now: Date) {
        guard let lastSync else {
            self = .never
            return
        }
        // A timestamp in the future (clock change, restored backup) is not
        // stale. `SyncTimeFormatter` reads it as "just now" for the same
        // reason, and a stale badge on data the device believes is newer than
        // the current time would only look like a bug.
        let age = now.timeIntervalSince(lastSync)
        self = age > Self.staleThreshold ? .stale : .fresh
    }

    /// Whether the user has something to act on — the row that earns the
    /// warning treatment and the retry button.
    var needsAttention: Bool {
        switch self {
        case .fresh: return false
        case .never, .stale: return true
        }
    }
}
