import Foundation

/// Who answered the analysis on screen, and who was asked before them (#79).
///
/// Published beside `AnalysisState` rather than folded into it, in the same
/// spirit as `lockMessage` and `isTakingLong`: attribution outlives the
/// state transitions it spans — the same provider is named while loading,
/// while streaming, and on the finished result — so threading it through every
/// case would repeat one fact four times.
struct AnalysisAttribution: Equatable {
    /// Every provider tried in this run, in the user's priority order. The
    /// last one is answering now, or answered; the ones before it failed.
    private(set) var attempted: [LLMProvider]

    init(first provider: LLMProvider) {
        attempted = [provider]
    }

    /// The provider answering right now, or the one that produced the result.
    var provider: LLMProvider {
        // `attempted` is never empty: the only initialiser seeds it and
        // `append` only grows it.
        attempted[attempted.count - 1]
    }

    /// Whether an earlier provider failed and handed over. Drives the inline
    /// fallback notice on the result.
    var didFallBack: Bool { attempted.count > 1 }

    /// Everyone who was tried and failed, in order — empty when the user's
    /// first choice answered.
    var failedProviders: [LLMProvider] { attempted.dropLast() }

    /// Records that the chain has moved on to `provider`.
    mutating func append(_ provider: LLMProvider) {
        attempted.append(provider)
    }

    /// `"Claude unavailable — answered by Gemini"`, or with more than one
    /// failure `"Claude and Gemini unavailable — answered by Mistral"`.
    ///
    /// `nil` when nothing was fallen back from, so the caller drops the notice
    /// rather than rendering an empty one.
    var fallbackNotice: String? {
        guard didFallBack else { return nil }
        return "\(Self.list(failedProviders)) unavailable — answered by \(provider.displayName)"
    }

    /// `[a]` → `"A"`, `[a, b]` → `"A and B"`, `[a, b, c]` → `"A, B and C"`.
    ///
    /// Written out rather than using `ListFormatter`: the app's text is English
    /// only (see CLAUDE.md), so a locale-aware formatter would only introduce a
    /// mismatch with the sentence it is embedded in.
    private static func list(_ providers: [LLMProvider]) -> String {
        let names = providers.map(\.displayName)
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
