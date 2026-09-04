import Foundation

/// Turns a provider's answer into the blocks the analysis screen renders
/// (#117).
///
/// The system prompt asks for prose and says nothing about Markdown, but every
/// provider structures its recommendation anyway — `**Progressive Overload**`
/// as a heading, `- ` for the steps. Rendered as one string, that is a wall of
/// text with asterisks in it: exactly the paid-for answer, at its least
/// readable.
///
/// So this reads the structure the model chose, defensively — heading,
/// paragraph, bullet, inline emphasis, and nothing else. Anything it does not
/// recognise stays prose, which is what an answer without a single marker is
/// made of entirely.
///
/// Pure and stateless, so the result view, the streaming view and the history
/// preview all read the same text the same way.
enum AnalysisTextFormatter {
    /// Parses `raw` into the blocks to render, in order.
    ///
    /// Safe to call on a partial answer: a marker the stream has not closed yet
    /// is dropped rather than shown, so no asterisk and no premature heading
    /// flashes up mid-run.
    static func blocks(from raw: String) -> [AnalysisTextBlock] {
        var blocks: [AnalysisTextBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
            paragraph = []
        }

        for line in normalizedEmphasis(raw).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let item = bulletItem(in: trimmed) {
                flushParagraph()
                blocks.append(.bullet(inline(item)))
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }

    /// The same text with every marker resolved away — the two-line preview in
    /// the history list and the VoiceOver label under it, neither of which may
    /// read out an asterisk.
    static func plainText(from raw: String) -> String {
        blocks(from: raw)
            .map { block in
                switch block {
                case .heading(let text):
                    return text
                case .paragraph(let text), .bullet(let text):
                    return String(text.characters)
                }
            }
            .joined(separator: "\n")
    }

    // MARK: - Lines

    /// The heading a line carries, or `nil` if it is not one.
    ///
    /// Two spellings, both seen from the providers: a line that is entirely
    /// bold, and an ATX `#` line. A trailing colon goes with the markers — the
    /// heading style already separates the title from what follows, and
    /// "Progressive Overload:" set as a heading reads like a truncated
    /// sentence.
    private static func heading(in line: String) -> String? {
        if line.hasPrefix("#") {
            let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return withoutTrailingColon(unwrappingBold(title))
        }
        guard line.hasPrefix("**") else { return nil }
        // Everything after the opening marker has to be one bold run: a line
        // that merely *starts* bold ("**Bench press** stalled at 60 kg") is a
        // sentence, not a title.
        let body = withoutTrailingColon(line)
        guard body.hasSuffix("**"), body.count > 4 else { return nil }
        let inner = String(body.dropFirst(2).dropLast(2))
        guard !inner.isEmpty, !inner.contains("*") else { return nil }
        return withoutTrailingColon(inner)
    }

    /// The content of a list item, or `nil` if the line is not one.
    ///
    /// The marker itself is dropped: the view draws the bullet, so a model that
    /// writes "-" and one that writes "1." produce the same list instead of one
    /// with the characters showing.
    private static func bulletItem(in line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func unwrappingBold(_ text: String) -> String {
        guard text.hasPrefix("**"), text.hasSuffix("**"), text.count > 4 else { return text }
        return String(text.dropFirst(2).dropLast(2))
    }

    private static func withoutTrailingColon(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }

    // MARK: - Inline

    /// Resolves `**bold**` and `*italic*` inside one block.
    ///
    /// Inline-only: a full Markdown pass would re-interpret the line breaks and
    /// list markers this formatter has already decided about. A text the parser
    /// rejects falls back to itself, minus the escapes that were only ever for
    /// that parser — an unreadable answer is still the answer the user paid
    /// for, and no `try!` belongs on a provider's output.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            // The escapes `normalizedEmphasis(_:)` added are for the parser
            // that just refused the text; showing them raw would put a
            // backslash on screen instead of the asterisk they protect.
            return AttributedString(text.replacingOccurrences(of: "\\*", with: "*"))
        }
        return parsed
    }

    /// Settles every `*` in the text before the parser sees it: the ones that
    /// are markers, the ones that are not, and the one the stream has not
    /// finished writing.
    ///
    /// - A marker the text never closes — the half-written `**` at the end of a
    ///   streaming answer — is dropped. Only the marker goes; the words after
    ///   it stay visible and simply grow as the stream continues, so the line
    ///   does not jump when the pair completes.
    /// - A `*` between two digits is a set scheme ("3*5"), and is escaped so
    ///   the parser leaves it alone. Escaped rather than merely skipped: two of
    ///   them in one answer ("3*5 and 4*8") are a valid emphasis pair to
    ///   Markdown, which would render them as "35 and 48".
    /// - A `*` surrounded by spaces ("5 * 5 sets") is no delimiter to Markdown
    ///   either way, and is left exactly as it is.
    private static func normalizedEmphasis(_ text: String) -> String {
        var doubles: [Range<String.Index>] = []
        var singles: [Range<String.Index>] = []
        var literals: [Range<String.Index>] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "*" else {
                index = text.index(after: index)
                continue
            }
            var end = index
            while end < text.endIndex, text[end] == "*" {
                end = text.index(after: end)
            }
            let run = index..<end
            if text.distance(from: index, to: end) >= 2 {
                doubles.append(index..<text.index(index, offsetBy: 2))
            } else if isBetweenDigits(runAt: run, in: text) {
                literals.append(run)
            } else if isFlanking(runAt: run, in: text) {
                singles.append(run)
            }
            index = end
        }

        var edits: [(range: Range<String.Index>, replacement: String)] = []
        if doubles.count.isMultiple(of: 2) == false, let last = doubles.last {
            edits.append((last, ""))
        }
        if singles.count.isMultiple(of: 2) == false, let last = singles.last {
            edits.append((last, ""))
        }
        edits.append(contentsOf: literals.map { ($0, "\\*") })
        guard !edits.isEmpty else { return text }

        var result = text
        // Back to front, so an earlier edit cannot invalidate a later range.
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.replacement)
        }
        return result
    }

    /// Whether a `*` run sits between two digits — "3*5", a set scheme rather
    /// than emphasis.
    ///
    /// False at the very end of the text: there the digit is simply the last
    /// thing that has arrived, and the asterisk is a marker mid-stream.
    private static func isBetweenDigits(runAt range: Range<String.Index>, in text: String) -> Bool {
        guard range.upperBound < text.endIndex, text[range.upperBound].isNumber,
              range.lowerBound > text.startIndex
        else { return false }
        return text[text.index(before: range.lowerBound)].isNumber
    }

    /// Whether a `*` run touches a word on either side — Markdown's condition
    /// for it to open or close emphasis at all.
    ///
    /// A run at the very end of the text always counts: mid-stream that is a
    /// marker whose word has not arrived yet, and leaving it in would put the
    /// one asterisk on screen that this whole pass exists to prevent.
    private static func isFlanking(runAt range: Range<String.Index>, in text: String) -> Bool {
        guard range.upperBound < text.endIndex else { return true }
        let precedesWord = !text[range.upperBound].isWhitespace
        let followsWord = range.lowerBound > text.startIndex
            && !text[text.index(before: range.lowerBound)].isWhitespace
        return precedesWord || followsWord
    }
}
