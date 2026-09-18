import Foundation

/// An `AnalysisReport` after `AnalysisReportValidator` has checked every card
/// against the cache (US-14 AC3/AC4, #175) — what the result screen renders
/// (#177) and the history persists (#176).
///
/// Lead and summary are the model's, unchanged, and so are headline and
/// verdict unless the recovery hint overrides them. The cards are not: a card
/// whose figures the cache does not confirm is a `.note`, and a week that
/// calls for recovery always carries a recovery card. A report without cards
/// is valid — thin data has a lead and a summary, no filler cards (#170).
struct ValidatedAnalysisReport: Codable, Equatable, Sendable {
    let headline: String
    let verdict: AnalysisVerdict
    /// The key takeaway in one to three sentences (#170).
    let lead: String
    let cards: [AnalysisReportCard]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case headline, verdict, lead, cards, summary
    }
}

extension ValidatedAnalysisReport {
    /// Decodes a stored report, including one written before the lead existed
    /// (#170): a missing or blank `lead` is derived from `summary`, the same
    /// way `AnalysisReportParser` does for an answer. Such rows only exist on
    /// unreleased builds, so the stored format stays version 1
    /// (`AnalysisReportFormat.validatedReportV1`). Declared in an extension so
    /// the memberwise initialiser stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = try container.decode(String.self, forKey: .summary)
        self.init(
            headline: try container.decode(String.self, forKey: .headline),
            verdict: try container.decode(AnalysisVerdict.self, forKey: .verdict),
            lead: AnalysisLead.resolved(
                try container.decodeIfPresent(String.self, forKey: .lead) ?? "",
                summary: summary
            ),
            cards: try container.decode([AnalysisReportCard].self, forKey: .cards),
            summary: summary
        )
    }
}

extension ValidatedAnalysisReport {
    /// Whether the lead has text to show (#170).
    var hasLead: Bool {
        !Self.normalized(lead).isEmpty
    }

    /// Whether the "Show full analysis" disclosure has anything to add: the
    /// summary has text, and it is more than the lead once more (#170). A
    /// summary that equals the lead, or that the lead already contains, would
    /// only repeat it.
    var hasFullAnalysis: Bool {
        let summary = Self.normalized(AnalysisTextFormatter.plainText(from: self.summary))
        guard !summary.isEmpty else { return false }
        let lead = Self.normalized(lead)
        return lead.isEmpty || !lead.contains(summary)
    }

    /// `text` trimmed, with every run of whitespace collapsed to one space and
    /// compared case-insensitively.
    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
