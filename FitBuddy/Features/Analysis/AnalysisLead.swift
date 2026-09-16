import Foundation

/// The short takeaway above the cards (US-14 AC1, #170), and how it is
/// rebuilt from the full analysis when an answer or a stored report has none.
enum AnalysisLead {
    /// Sentences a derived lead takes from the summary at most.
    static let maxSentences = 2

    /// Words a derived lead holds at most — the prompt's "about 50 words".
    static let maxWords = 50

    /// Abbreviations whose period does not end a sentence, lowercased and
    /// without their final period.
    static let abbreviations: Set<String> = [
        "approx", "ca", "e.g", "i.e", "vs", "incl", "avg", "esp", "resp", "cf"
    ]

    /// The first sentence or two of `summary`'s prose, within `maxWords`.
    ///
    /// Read through `AnalysisTextFormatter`, so a summary the model structured
    /// with Markdown gives a plain lead: headings and list items are skipped,
    /// emphasis markers are resolved away. Only a summary that is nothing but
    /// a list falls back to its items.
    ///
    /// A second sentence is only added while the lead stays within the limit.
    /// A first sentence longer than that is cut after `maxWords` words and
    /// marked with an ellipsis, so an answer without punctuation cannot turn
    /// the whole summary into its lead. Empty when `summary` has no text.
    static func derived(from summary: String) -> String {
        let sentences = Self.sentences(in: prose(of: summary))
        guard let first = sentences.first else { return "" }

        let firstWords = words(in: first)
        guard firstWords.count <= maxWords else {
            return firstWords.prefix(maxWords).joined(separator: " ") + "…"
        }
        var lead = [first]
        var count = firstWords.count
        for sentence in sentences.dropFirst().prefix(maxSentences - 1) {
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

    // MARK: - Prose

    /// The paragraphs of `summary` as plain text, or its list items when it
    /// has no paragraph at all.
    private static func prose(of summary: String) -> String {
        var paragraphs: [String] = []
        var items: [String] = []
        for block in AnalysisTextFormatter.blocks(from: summary) {
            switch block {
            case .heading:
                continue
            case .paragraph(let text):
                paragraphs.append(String(text.characters))
            case .bullet(let text):
                items.append(String(text.characters))
            }
        }
        return (paragraphs.isEmpty ? items : paragraphs).joined(separator: " ")
    }

    /// `text` split after `.`, `!` or `?` followed by whitespace — except after
    /// a known abbreviation, or before a lowercase word, where a period does
    /// not end a sentence. Decimals ("62.5 kg") have no whitespace after the
    /// period and never split.
    private static func sentences(in text: String) -> [String] {
        let tokens = words(in: text)
        var sentences: [String] = []
        var current: [String] = []
        for (index, token) in tokens.enumerated() {
            current.append(token)
            guard let last = token.last, ".!?".contains(last) else { continue }
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if last == ".", isAbbreviation(token) { continue }
            if let first = next?.first, first.isLowercase { continue }
            sentences.append(current.joined(separator: " "))
            current = []
        }
        if !current.isEmpty {
            sentences.append(current.joined(separator: " "))
        }
        return sentences
    }

    private static func isAbbreviation(_ token: String) -> Bool {
        let bare = token.dropLast().lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(\"'"))
        return abbreviations.contains(bare)
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
