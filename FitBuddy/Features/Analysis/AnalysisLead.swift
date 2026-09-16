import Foundation

/// The short takeaway above the cards (US-14 AC1, #170), and how it is
/// rebuilt from the full analysis when an answer or a stored report has none.
enum AnalysisLead {
    /// Sentences a derived lead takes from the summary at most.
    static let maxSentences = 2

    /// Words a derived lead holds at most — the prompt's "about 50 words".
    static let maxWords = 50

    /// The first sentence or two of `summary`, within `maxWords`.
    ///
    /// A second sentence is only added while the lead stays within the limit.
    /// A first sentence longer than that is cut after `maxWords` words and
    /// marked with an ellipsis, so an answer without punctuation cannot turn
    /// the whole summary into its lead. Empty when `summary` is blank.
    static func derived(from summary: String) -> String {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, stop in
            guard let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sentence.isEmpty
            else { return }
            sentences.append(sentence)
            if sentences.count == maxSentences { stop = true }
        }
        guard let first = sentences.first else { return "" }

        let firstWords = words(in: first)
        guard firstWords.count <= maxWords else {
            return firstWords.prefix(maxWords).joined(separator: " ") + "…"
        }
        var lead = [first]
        var count = firstWords.count
        for sentence in sentences.dropFirst() {
            count += words(in: sentence).count
            guard count <= maxWords else { break }
            lead.append(sentence)
        }
        return lead.joined(separator: " ")
    }

    /// `lead` when it has text, otherwise the lead derived from `summary`.
    static func resolved(_ lead: String, summary: String) -> String {
        isBlank(lead) ? derived(from: summary) : lead
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
