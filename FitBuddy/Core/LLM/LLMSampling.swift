import Foundation

/// The sampling parameters the analysis calls use, in one place (#226, US-16
/// AC2).
///
/// Per provider:
/// - **Claude** — nothing. `temperature` and friends are rejected with HTTP
///   400 on `claude-opus-5`, and the Messages API has no seed (see
///   `ClaudeMessageRequest`).
/// - **Gemini** — nothing. Whether `gemini-3.6-flash` accepts `seed` is
///   unverified: the live test on 26.09.2026 only returned HTTP 503
///   (overload), and an unknown `generationConfig` key would be an HTTP 400
///   that breaks the Gemini fallback. So it is deliberately not sent and
///   Gemini runs on provider defaults; revisit only with a verified live call
///   (see `GeminiGenerateContentRequest`).
/// - **Mistral** — the fixed `seed` below as `random_seed` (live-verified
///   26.09.2026, HTTP 200).
///
/// In practice that makes this type Mistral-only today; it stays the single
/// place so that any provider that gains a verified seed reads the same value.
///
/// Its own type rather than properties on `LLMProvider`: that enum models what
/// the *user* deals with — which providers a key can be entered for, where to
/// get one, what the key looks like. These constants are wire-level decoding
/// settings meant to be identical for every provider that takes them. Per-provider
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
/// revisiting these points. `AnthropicClient` and `GeminiClient` take no
/// sampling field at all; the Gemini and Mistral tests assert that no
/// `temperature` key is sent, and the Gemini tests that no `seed` is sent.
enum LLMSampling {
    /// Fixed seed for the providers verified to accept one — currently only
    /// Mistral (`random_seed`). Not sent to Gemini (unverified, see above).
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
