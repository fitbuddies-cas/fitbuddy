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
/// **Seed only — no temperature, on purpose.** Every provider runs at its own
/// default temperature, and that absence is a decision, not an oversight (#224
/// AC2):
///
/// 1. Verdict stability comes from #227 — the app derives the verdict from its
///    own metrics. After that, temperature only affects wording and card
///    choice, which US-16 AC1 allows to vary.
/// 2. The primary provider, Claude Opus 5, rejects `temperature` with HTTP 400
///    (see `ClaudeMessageRequest`). A lowered value would only make the
///    fallback providers behave differently from the primary one.
/// 3. Even `temperature = 0` is not deterministic behind a public API: the
///    study #224 cites found outputs still varying because of batch-dependent
///    GPU kernels, not sampling.
/// 4. Both fallback models reason before answering. Google advises keeping
///    Gemini 3 models at the default temperature 1.0 (lower values risk
///    looping or degraded output); Mistral recommends about 0.7 for its
///    reasoning models. A low value like 0.2 risks silent quality loss.
///
/// Do not add a temperature here to make the providers "consistent" without
/// revisiting these points. `AnthropicClient` takes no sampling field at all;
/// the Gemini and Mistral tests assert that no `temperature` key is sent.
enum LLMSampling {
    /// Fixed seed for the providers that accept one (Mistral `random_seed`,
    /// Gemini `seed`).
    ///
    /// Costs nothing and adds best-effort reproducibility where it is offered.
    /// The value is arbitrary; that it never changes between runs is the whole
    /// point. With an identical prompt and a fixed seed, the provider samples
    /// the same way twice — as far as its own scheduling allows (point 3
    /// above). A fixed value is the only variant that buys anything: omitting
    /// the field lets the provider pick a seed per request, so sending a
    /// freshly drawn one each run is *equivalent* to omitting it — not worse,
    /// just pointless.
    static let seed = 1
}
