import Foundation

/// The sampling parameters every analysis call uses, in one place (#226, US-16
/// AC2).
///
/// Its own type rather than properties on `LLMProvider`: that enum models what
/// the *user* deals with — which providers a key can be entered for, where to
/// get one, what the key looks like. These constants are wire-level decoding
/// settings that are identical across providers by design. Per-provider
/// computed properties there would invite exactly the divergence this task
/// removes, and it would tie an onboarding type to request bodies. One type per
/// file (CLAUDE.md), so it lives here next to `LLMProvider` in `Core/LLM/`
/// rather than in any single client — the point of the task is that the clients
/// read from one definition instead of carrying three copies.
///
/// Not every provider takes both fields; `AnthropicClient` takes neither. See
/// `ClaudeMessageRequest` for why, and keep that documented rather than silent.
enum LLMSampling {
    /// Low, but deliberately not 0.
    ///
    /// The problem being solved is that the same cache and the same prompt
    /// produced three different verdicts in three runs (#224). Temperature is
    /// the part of that FitBuddy can actually turn down: it narrows the
    /// distribution the next token is drawn from, so the model stops wandering
    /// between defensible readings of the same numbers.
    ///
    /// 0 is not the better choice here for two reasons. It buys no real
    /// determinism — the measurement in #224 found the outputs still vary at
    /// `temperature = 0`, because the cause is the batch dependence of the GPU
    /// kernels behind a public API, not the sampling. And it costs something:
    /// the report is prose the user reads, and greedy decoding makes it flat
    /// and repetitive, headline and lead falling into the same phrasing every
    /// time. 0.2 keeps the wording alive while cutting the spread that made the
    /// recommendation impossible to follow.
    ///
    /// The verdict itself does not become stable from this alone — #227 moves
    /// it out of the model and into the app's own metrics. This only lowers the
    /// spread where the provider lets it.
    static let temperature = 0.2

    /// Fixed seed for the providers that accept one (Mistral `random_seed`,
    /// Gemini `seed`).
    ///
    /// The value is arbitrary; that it never changes between runs is the whole
    /// point. With an identical prompt and a fixed seed, the provider samples
    /// the same way twice — as far as its own scheduling allows, which is the
    /// same caveat as above. A per-run seed would be strictly worse than none,
    /// as it would guarantee the variation instead of merely permitting it.
    static let seed = 1
}
