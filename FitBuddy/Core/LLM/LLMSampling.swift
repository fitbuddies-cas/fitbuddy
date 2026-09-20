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
    /// Why not 0. Greedy decoding would not buy the determinism it looks like
    /// it buys: the study #224 cites (arXiv 2604.19598 / PMID 42435611) found
    /// outputs still varying at `temperature = 0`, because the cause is the
    /// batch dependence of the GPU kernels behind a public API rather than the
    /// sampling. That study covers GPT-4.1 and Claude Sonnet 4.6 — **not**
    /// Gemini and Mistral, the only two providers this constant reaches — so it
    /// is an argument by analogy, not a result measured on our own stack. The
    /// remaining reason to stay off 0 is that greedy decoding on a structured
    /// JSON answer can fall into degenerate repetition, and the report is prose
    /// the user reads.
    ///
    /// **0.2 is a judgement call, not a measured optimum.** Nothing in this
    /// repo has compared it against 0, 0.3 or 0.7, and #229 is the task that
    /// measures what spread is actually left. Treat the number as revisable.
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
    /// same caveat as above. A fixed value is the only variant that buys
    /// anything: omitting the field lets the provider pick a seed per request,
    /// so sending a freshly drawn one each run is *equivalent* to omitting it —
    /// not worse, just pointless.
    static let seed = 1
}
