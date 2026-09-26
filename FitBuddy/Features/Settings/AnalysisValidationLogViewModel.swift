import Foundation
import OSLog

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// Drives the developer view of the validation log (US-16 AC4, #228): per
/// stored analysis, who answered, the model's verdict against the app's, and
/// every intervention — plus the tally across all of them, which is what
/// #229 reads the hit rate from.
///
/// Read-only. The log is written by `AnalysisViewModel` with each analysis
/// and deleted with it; nothing here changes the store.
@MainActor
final class AnalysisValidationLogViewModel: ObservableObject {
    /// The stored analyses that carry a log, newest first.
    @Published private(set) var entries: [AnalysisValidationLogEntry] = []
    /// The aggregate over `entries`.
    @Published private(set) var tally = AnalysisValidationTally(logs: [])
    /// Stored analyses without a log: prose answers and rows written before
    /// V7. Named apart so they are not mistaken for clean runs.
    @Published private(set) var unrecordedCount = 0
    /// Whether the store has been read at least once.
    @Published private(set) var isLoaded = false
    /// Set when the store could not be read.
    @Published private(set) var failure: String?

    private let store: any AnalysisResultStoring

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    init(store: any AnalysisResultStoring) {
        self.store = store
    }

    /// Reads every stored analysis — at most `AnalysisHistoryLimit.rows`.
    func load() async {
        do {
            let stored = try await store.recent(limit: AnalysisHistoryLimit.rows)
            entries = stored.compactMap { snapshot in
                snapshot.validationLog.map {
                    AnalysisValidationLogEntry(id: snapshot.id, generatedAt: snapshot.generatedAt, log: $0)
                }
            }
            tally = AnalysisValidationTally(logs: entries.map(\.log))
            unrecordedCount = stored.count - entries.count
            failure = nil
        } catch {
            logger.error("Validation logs not readable: \(error, privacy: .public)")
            failure = "The stored analyses could not be read."
        }
        isLoaded = true
    }

    /// "Claude · claude-opus-5", or what of it the log recorded.
    static func source(of log: AnalysisValidationLog) -> String {
        let provider = log.provider?.displayName ?? "Unknown provider"
        guard let model = log.model else { return provider }
        return "\(provider) · \(model)"
    }

    /// "progress → hold (noNewBest)", or "hold (noNewBest)" where the two
    /// agreed.
    static func verdictLine(of log: AnalysisValidationLog) -> String {
        let app = "\(log.appVerdict.rawValue) (\(log.verdictReason.rawValue))"
        guard log.verdictOverridden else { return app }
        return "\(log.modelVerdict.rawValue) → \(app)"
    }

    /// "progression downgraded: aboveRange", the head line of an
    /// intervention.
    static func title(of intervention: AnalysisIntervention) -> String {
        "\(intervention.subject.rawValue) \(intervention.action.rawValue): \(intervention.reason.rawValue)"
    }

    /// "proposed 70 kg · app 60 kg · allowed 62.5–65 kg", or `nil` for an
    /// intervention without figures.
    static func figureLine(of intervention: AnalysisIntervention) -> String? {
        guard let figure = intervention.figure else { return nil }
        let unit = figure.unit.symbol
        var parts = ["proposed \(number(figure.proposed)) \(unit)"]
        if let app = figure.app {
            parts.append("app \(number(app)) \(unit)")
        }
        if let min = figure.allowedMin, let max = figure.allowedMax {
            parts.append("allowed \(number(min))–\(number(max)) \(unit)")
        }
        return parts.joined(separator: " · ")
    }

    /// A figure with up to two decimals and no trailing zeros.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

#endif
