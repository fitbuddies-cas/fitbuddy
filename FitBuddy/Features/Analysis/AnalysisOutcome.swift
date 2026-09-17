import Foundation

/// What a finished analysis produced (US-14, #178): the validated report the
/// cards are built from, or prose when the answer was not a report.
///
/// Carried by `AnalysisState.result`. The provider that wrote it is not part
/// of the outcome — it lives in `AnalysisAttribution`, which spans the whole
/// run, not just its result.
enum AnalysisOutcome: Equatable, Sendable {
    /// A structured answer, checked against the cache (#175).
    case report(ValidatedAnalysisReport)
    /// A prose answer: a provider without JSON output, a non-conforming answer
    /// (US-14 AC5), a stored row from before V4, or a report that could not be
    /// validated.
    case prose(String)

    /// The outcome as prose: the text itself, or the report's summary. What
    /// the history stores as the prose fallback of every row (#176).
    var text: String {
        switch self {
        case .report(let report):
            return report.summary
        case .prose(let text):
            return text
        }
    }

    /// The outcome a stored row renders as: its cards when it stored a report
    /// (#176), its text otherwise — every row from before V4 included (US-14
    /// AC6). Shared by the restored result and the history detail, so the two
    /// never show the same row differently.
    init(stored snapshot: AnalysisResultSnapshot) {
        guard let report = snapshot.report else {
            self = .prose(snapshot.text)
            return
        }
        self.init(validated: report)
    }

    /// The outcome a validated report renders as: always the report, with or
    /// without cards (#170). A report without cards is what thin data should
    /// produce — headline, lead and the full analysis opened below — and not a
    /// reason to fall back to prose.
    init(validated report: ValidatedAnalysisReport) {
        self = .report(report)
    }

    /// The validated report, or `nil` for prose.
    var report: ValidatedAnalysisReport? {
        guard case .report(let report) = self else { return nil }
        return report
    }
}
