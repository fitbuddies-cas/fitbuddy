import Foundation

/// One step of an analysis run (#79, #174).
///
/// The fallback chain needs to tell the screen three things — who is answering,
/// that a provider was given up on, and the answer itself — and all three have
/// to stay in order with each other. One stream of events does that; a second
/// published channel beside the answer would let the provider label and the
/// answer it belongs to arrive out of order.
enum AnalysisEvent: Equatable, Sendable {
    /// A provider is about to be tried. Everything received before this event
    /// came from a provider that has since failed and must be discarded — the
    /// user never sees two answers mixed together.
    case attempting(LLMProvider)
    /// Prose from the provider named by the last `attempting`. Since #174 the
    /// answer arrives in one piece, and this carries it whenever it is not a
    /// decodable `AnalysisReport` (US-14 AC5).
    case text(String)
    /// The complete, decoded answer of the provider named by the last
    /// `attempting` (US-14).
    case report(AnalysisReport)
}
