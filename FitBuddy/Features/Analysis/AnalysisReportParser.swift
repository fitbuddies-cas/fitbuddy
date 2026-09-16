import Foundation
import OSLog

/// Turns a provider's complete answer into what the screen shows: the decoded
/// `AnalysisReport`, or prose when the answer does not match the schema (US-14
/// AC5, #174).
///
/// Never fails. An answer that is not a report is still the model's
/// recommendation, so it falls back — first to the report's `summary` if that
/// much is readable, then to the raw text — instead of surfacing an error the
/// user can do nothing about.
enum AnalysisReportParser {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// `.report` for a decodable answer, `.text` with the prose fallback
    /// otherwise.
    static func event(for answer: String) -> AnalysisEvent {
        let data = Data(unfenced(answer).utf8)
        let decoder = JSONDecoder()
        do {
            return .report(try decoder.decode(AnalysisReport.self, from: data))
        } catch {
            // The detail can quote the model's text, i.e. training data: kept
            // private in the log.
            logger.notice("Analysis answer is not a report, falling back to prose: \(String(describing: error))")
        }
        if let summary = try? decoder.decode(Summary.self, from: data).summary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(summary)
        }
        return .text(answer)
    }

    /// The JSON inside a Markdown code fence, or the trimmed answer when it has
    /// none. Structured output does not fence its JSON, but a model answering
    /// without the schema often does.
    private static func unfenced(_ answer: String) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count > 6 else { return trimmed }
        let inner = trimmed.dropFirst(3).dropLast(3)
        // Drops the info string (`json`) on the opening line.
        guard let firstLineEnd = inner.firstIndex(of: "\n") else { return trimmed }
        return String(inner[firstLineEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The one field the prose fallback needs, readable even when the rest of
    /// the report is not.
    private struct Summary: Decodable {
        let summary: String
    }
}
