import Foundation

/// Wire body for a streaming call to Claude's `POST /v1/messages` (#29).
///
/// **No sampling fields here, on purpose (#226).** Gemini and Mistral both take
/// `temperature` and a seed from `LLMSampling`; Claude takes neither, and that
/// gap is a property of the API rather than an oversight:
///
/// - `temperature`, `top_p` and `top_k` are removed on `claude-opus-5`, the
///   model this client uses, because of its adaptive thinking. A request that
///   carries any of them is rejected with **HTTP 400** — adding one here would
///   break every analysis on FitBuddy's primary provider.
/// - The Messages API has no `seed` on any model, so there is nothing to pin
///   the sampling to either.
///
/// The only knob left is `output_config.effort` below, whose value is
/// `AnthropicClient.effort` — named rather than repeated here, so raising it
/// later cannot silently falsify this comment. The
/// spread this leaves on Claude is not closed from here; the verdict moves into
/// the app's own metrics in #227. `AnthropicClientTests` asserts that none of
/// the four field names reaches the wire, so that nobody adds them later in
/// good faith while making the three providers "consistent".
struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let stream: Bool
    let messages: [Message]
    let outputConfig: OutputConfig

    struct Message: Encodable {
        let role: String
        let content: String
    }

    /// How much reasoning the model spends before it answers, and the shape
    /// the answer has to take.
    struct OutputConfig: Encodable {
        let effort: String
        let format: Format
    }

    /// Structured output (#174): constrains the answer to `schema`.
    ///
    /// Claude's dialect: every object needs `additionalProperties: false`;
    /// `enum`, `const`, `anyOf`, `required` and `description` are supported;
    /// numeric and string bounds (`minimum`, `maxLength`, …) and `minItems`
    /// above 1 are not. The text deltas of the stream are then fragments of
    /// one JSON document.
    struct Format: Encodable {
        let type = "json_schema"
        let schema: JSONValue
    }

    enum CodingKeys: String, CodingKey {
        case model, system, stream, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}
