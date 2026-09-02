import Foundation

extension AttributedString {
    /// Parses `markdown` for display, falling back to the raw text if it does
    /// not parse. Every "where to find your key" card renders provider copy
    /// that carries bold markers, and `Text(_: AttributedString)` — unlike
    /// `Text(_: LocalizedStringKey)` — does no markdown parsing of its own.
    static func markdownOrPlain(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
