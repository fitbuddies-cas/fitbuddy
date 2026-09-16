import Foundation
import OSLog

/// Turns a provider's complete answer into what the screen shows: the decoded
/// `AnalysisReport`, prose when the answer does not match the schema (US-14
/// AC5), or nothing when there is no usable answer at all (#174).
///
/// The fallbacks, in order:
///
/// 1. The answer decodes as a report — directly, out of a code fence, or from
///    its first `{` to its last `}`. A blank `summary` is rebuilt from the
///    headline and the cards, so every report carries usable prose.
/// 2. A complete top-level `summary` string can be read out of the JSON, even
///    when the document around it is invalid or cut off at the token limit.
/// 3. The answer is not JSON at all: it is the model's prose, shown as is.
/// 4. Otherwise — blank, or JSON with no readable summary, typically truncated
///    before it — `nil`. Raw JSON is not a recommendation, so the caller treats
///    this like an unreadable response and moves on to the next provider.
enum AnalysisReportParser {
    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// `.report` for a decodable answer, `.text` with the prose fallback, or
    /// `nil` when the answer holds nothing to show.
    static func event(for answer: String) -> AnalysisEvent? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let body = unfenced(trimmed)

        if let report = decodedReport(from: body) {
            return withProse(report).map(AnalysisEvent.report)
        }
        if let span = braced(body), span != body, let report = decodedReport(from: span) {
            return withProse(report).map(AnalysisEvent.report)
        }
        if let jsonStart = body.firstIndex(of: "{"),
           let summary = salvagedSummary(from: body[jsonStart...]) {
            return .text(summary)
        }
        // Only an answer that is JSON from its first character counts as a
        // failed document; anything else is the model writing prose.
        return body.hasPrefix("{") ? nil : .text(trimmed)
    }

    // MARK: - Report

    private static func decodedReport(from json: String) -> AnalysisReport? {
        do {
            return try JSONDecoder().decode(AnalysisReport.self, from: Data(json.utf8))
        } catch {
            // The detail can quote the model's text, i.e. training data: kept
            // private in the log.
            logger.notice("Analysis answer is not a report: \(String(describing: error))")
            return nil
        }
    }

    /// `report`, with a blank `summary` rebuilt from the headline and one line
    /// per card — or `nil` when that leaves nothing to read either.
    private static func withProse(_ report: AnalysisReport) -> AnalysisReport? {
        guard isBlank(report.summary) else { return report }
        let lines = ([report.headline] + report.cards.map(\.prose)).filter { !isBlank($0) }
        guard !lines.isEmpty else { return nil }
        return AnalysisReport(
            headline: report.headline,
            verdict: report.verdict,
            cards: report.cards,
            summary: lines.joined(separator: "\n")
        )
    }

    // MARK: - Unwrapping

    /// The answer without a surrounding Markdown code fence. Structured output
    /// does not fence its JSON, but a model answering without the schema often
    /// does — on one line or several, and a truncated one without the closing
    /// fence.
    private static func unfenced(_ answer: String) -> String {
        guard answer.hasPrefix("```") else { return answer }
        var inner = answer.dropFirst(3)
        if inner.hasSuffix("```") { inner = inner.dropLast(3) }
        // The info string (`json`) directly after the opening fence.
        inner = inner.drop { $0.isLetter }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The span from the first `{` to the last `}` — the last resort for JSON
    /// with text around it, e.g. a sentence in front of a fence.
    private static func braced(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    // MARK: - Summary salvage

    /// The top-level `summary` string of `json`, provided the string itself is
    /// complete — the rest of the document may be invalid or cut off.
    ///
    /// Walks the text as JSON tokens rather than searching for `"summary"`, so
    /// the word inside another string, or a `summary` key nested deeper, cannot
    /// match. Scalars rather than characters: a combining mark after a quote
    /// would otherwise hide the quote inside one grapheme.
    private static func salvagedSummary(from json: Substring) -> String? {
        let scalars = json.unicodeScalars
        var depth = 0
        var index = scalars.startIndex
        // The last complete string at depth 1 that nothing but whitespace has
        // followed yet — a key, if a colon comes next.
        var pendingKey: String?
        var expectsSummaryValue = false

        while index < scalars.endIndex {
            let scalar = scalars[index]
            switch scalar {
            case "\"":
                guard let token = stringToken(in: scalars, from: index) else { return nil }
                let (value, end) = token
                if expectsSummaryValue {
                    return isBlank(value) ? nil : value
                }
                pendingKey = depth == 1 ? value : nil
                index = end
                continue
            case ":":
                expectsSummaryValue = pendingKey == "summary"
                pendingKey = nil
            case "{", "[":
                depth += 1
                pendingKey = nil
                expectsSummaryValue = false
            case "}", "]":
                depth -= 1
                pendingKey = nil
                expectsSummaryValue = false
            default:
                if !scalar.properties.isWhitespace {
                    pendingKey = nil
                    expectsSummaryValue = false
                }
            }
            index = scalars.index(after: index)
        }
        return nil
    }

    /// The decoded JSON string starting at the quote at `start`, and the index
    /// just past its closing quote — `nil` when the string never closes.
    private static func stringToken(
        in scalars: Substring.UnicodeScalarView,
        from start: Substring.UnicodeScalarView.Index
    ) -> (String, Substring.UnicodeScalarView.Index)? {
        var index = scalars.index(after: start)
        var isEscaped = false
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if isEscaped {
                isEscaped = false
            } else if scalar == "\\" {
                isEscaped = true
            } else if scalar == "\"" {
                let end = scalars.index(after: index)
                let literal = Data(String(scalars[start..<end]).utf8)
                guard let value = try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed) as? String
                else { return nil }
                return (value, end)
            }
            index = scalars.index(after: index)
        }
        return nil
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
