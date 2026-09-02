import Foundation

/// One step of a streamed analysis run (#79).
///
/// The fallback chain needs to tell the screen three things — who is answering,
/// that a provider was given up on, and the text itself — and all three have to
/// stay in order with each other. One stream of events does that; a second
/// published channel beside the text would let the provider label and the text
/// it belongs to arrive out of order.
enum AnalysisEvent: Equatable {
    /// A provider is about to be tried. Everything streamed before this event
    /// came from a provider that has since failed and must be discarded — the
    /// user never sees two answers mixed together.
    case attempting(LLMProvider)
    /// Incremental text from the provider named by the last `attempting`.
    case text(String)
}
