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
///    headline, the lead and the cards, so every report carries usable prose;
///    a blank or missing `lead` is derived from the summary (#170).
/// 2. A complete top-level `summary` string — or, failing that, a complete
///    top-level `lead` — can be read out of the JSON, even when the document
///    around it is invalid or cut off at the token limit.
/// 3. The answer is not JSON at all: it is the model's prose, shown as is.
/// 4. Otherwise — blank, or JSON with no readable summary or lead, typically
///    truncated before them — `nil`. Raw JSON is not a recommendation, so the
///    caller treats this like an unreadable response and moves on to the next
///    provider.
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
        if let jsonStart = body.firstIndex(of: "{") {
            let json = body[jsonStart...]
            if let prose = salvagedString(forKey: "summary", from: json)
                ?? salvagedString(forKey: "lead", from: json) {
                return .text(prose)
            }
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

    /// `report`, with a blank `summary` rebuilt from the headline, the lead and
    /// one line per card, and a blank `lead` derived from the summary — or
    /// `nil` when that leaves nothing to read either.
    ///
    /// A lead derived from a rebuilt summary skips the headline, which the
    /// screen already shows right above it.
    private static func withProse(_ report: AnalysisReport) -> AnalysisReport? {
        var summary = report.summary
        var leadSource = summary
        if isBlank(summary) {
            let body = ([report.lead] + report.cards.map(\.prose)).filter { !isBlank($0) }
            let lines = ([report.headline] + body).filter { !isBlank($0) }
            guard !lines.isEmpty else { return nil }
            summary = lines.joined(separator: "\n")
            leadSource = body.isEmpty ? summary : body.joined(separator: "\n")
        }
        return AnalysisReport(
            headline: report.headline,
            verdict: report.verdict,
            lead: AnalysisLead.resolved(report.lead, summary: leadSource),
            cards: report.cards,
            summary: summary
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

    // MARK: - Prose salvage

    /// The top-level string under `key` in `json`, provided the string itself
    /// is complete and not blank — the rest of the document may be invalid or
    /// cut off.
    ///
    /// Walks the text as JSON tokens rather than searching for `"summary"`, so
    /// the word inside another string, or a key nested deeper, cannot
    /// match. Scalars rather than characters: a combining mark after a quote
    /// would otherwise hide the quote inside one grapheme.
    private static func salvagedString(forKey key: String, from json: Substring) -> String? {
        let scalars = json.unicodeScalars
        var depth = 0
        var index = scalars.startIndex
        // The last complete string at depth 1 that nothing but whitespace has
        // followed yet — a key, if a colon comes next.
        var pendingKey: String?
        var expectsValue = false

        while index < scalars.endIndex {
            let scalar = scalars[index]
            switch scalar {
            case "\"":
                guard let token = stringToken(in: scalars, from: index) else { return nil }
                let (value, end) = token
                if expectsValue {
                    return isBlank(value) ? nil : value
                }
                pendingKey = depth == 1 ? value : nil
                index = end
                continue
            case ":":
                expectsValue = pendingKey == key
                pendingKey = nil
            case "{", "[":
                depth += 1
                pendingKey = nil
                expectsValue = false
            case "}", "]":
                depth -= 1
                pendingKey = nil
                expectsValue = false
            default:
                if !scalar.properties.isWhitespace {
                    pendingKey = nil
                    expectsValue = false
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
