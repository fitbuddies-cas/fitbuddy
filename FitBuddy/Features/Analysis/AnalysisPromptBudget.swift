import Foundation

/// The size one analysis prompt may reach, and the estimate it is measured
/// with (TD-1, US-15 AC8, #187).
///
/// Until now nothing bounded the prompt. Every cap in it — 30 listed
/// sessions, 10 listed exercises — was chosen for signal, not for size, and
/// `docs/ARCHITECTURE.md` recorded the gap as TD-1: *"Kein Token-Limit im
/// Prompt-Build"*, with `400 context_length_exceeded` over 90 days of full
/// training volume as the consequence. This type is the limit, and
/// `AnalysisPromptDetail` is what the builder gives up when it is reached.
///
/// ## Where the number comes from
///
/// FitBuddy sends the same prompt to whichever of the three configured
/// providers answers first (#79), so the budget has to hold for the smallest
/// context window of the three:
///
/// | Provider | Model | Context window |
/// |---|---|---|
/// | Anthropic | `claude-opus-5` | 1 M tokens |
/// | Google | `gemini-3.6-flash` | 1 M tokens |
/// | Mistral | `mistral-medium-3-5` | 128 k tokens |
///
/// `smallestContextWindowTokens` is therefore Mistral's 128 k. The budget is
/// not that number, for three reasons:
///
/// 1. the window also has to hold the answer (`maxTokens`, 8 192 tokens) and
///    the response schema every provider is sent alongside the prompt;
/// 2. `estimatedTokens(in:)` counts characters, and a prompt of dates, figures
///    and units tokenises at well under four characters per token — the
///    estimate is an undercount exactly where this prompt is densest;
/// 3. a prompt is not free and detail past a point stops being signal. The
///    largest prompt this app can build — a full 13-week cache of both
///    domains, four strength and four endurance sessions a week, 40 exercises
///    — measured about 16 200 characters, i.e. roughly 4 050 estimated tokens
///    (`AnalysisPromptBudgetTests.testTheWorstCaseLeavesHeadroom`). With the
///    effort values of #245 on every session and rule 8 it is about 5 350.
///
/// `maxPromptTokens` is a sixteenth of the smallest window, 8 000 tokens:
/// roughly one and a half times the largest prompt the app can build today
/// (twice, before #245 added effort), which leaves the
/// degradation ladder as a guard against a cache full of unusually long
/// user-written session and exercise titles rather than as something an
/// ordinary analysis runs into. **A provider with a smaller window than
/// Mistral's is what makes this constant wrong** — nothing else here depends
/// on it.
///
/// ## Per profile
///
/// US-15 AC1's three profiles carry very different bulk — an "Endurance"
/// analysis has no Exercises section and no session list at all. The budget is
/// still one number, because it is measured against the prompt that was
/// actually built: a single-domain profile simply arrives at the ladder with
/// half the prompt and never leaves the first rung. One constant, one
/// measurement, and no per-profile table to keep in sync with the sections.
enum AnalysisPromptBudget {
    /// The smallest context window among the three configured providers, in
    /// tokens — see the table above.
    static let smallestContextWindowTokens = 128_000

    /// What one prompt, system turn and user turn together, may reach.
    static let maxPromptTokens = smallestContextWindowTokens / 16

    /// Characters per estimated token.
    ///
    /// The rule of thumb for English prose, used deliberately rather than a
    /// tokeniser: none of the three providers has one that runs on device, a
    /// token-count endpoint would be a network round trip before every
    /// analysis, and the three tokenise differently anyway. What the budget
    /// needs is a cheap, deterministic **rough estimate, and this one
    /// undercounts dense and non-ASCII text**: a line of dates, figures and
    /// units tokenises at well under four characters per token, and a title in
    /// umlauts, Kanji or emoji costs more still. It is not an upper bound —
    /// the safety margin in `maxPromptTokens` is what pays for that.
    static let charactersPerEstimatedToken = 4

    /// The estimated token count of a piece of prompt text.
    ///
    /// Rounded up, so an empty string is 0 tokens and anything else is at
    /// least 1. `count` is the character count, not the UTF-8 length: an
    /// exercise title written in emoji or Kanji costs more tokens than this
    /// says, which is one more reason for the margin above.
    static func estimatedTokens(in text: String) -> Int {
        (text.count + charactersPerEstimatedToken - 1) / charactersPerEstimatedToken
    }

    /// The estimated token count of both turns of a prompt.
    static func estimatedTokens(of prompt: AnalysisPrompt) -> Int {
        estimatedTokens(in: prompt.system) + estimatedTokens(in: prompt.user)
    }

    /// Whether the two turns together stay inside the budget.
    static func fits(system: String, user: String) -> Bool {
        estimatedTokens(in: system) + estimatedTokens(in: user) <= maxPromptTokens
    }

    /// Whether a built prompt stays inside the budget.
    static func fits(_ prompt: AnalysisPrompt) -> Bool {
        estimatedTokens(of: prompt) <= maxPromptTokens
    }
}
