import Foundation

/// Wire body for a streaming call to Mistral's `POST /v1/chat/completions`
/// (#79).
///
/// OpenAI-shaped: the system prompt is the first message of the conversation,
/// not a separate field as with Claude and Gemini.
struct MistralChatRequest: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let messages: [Message]
    let responseFormat: ResponseFormat
    /// Sampling, from `LLMSampling` (#226). OpenAI-shaped here too, with one
    /// rename to watch: the seed field is `random_seed`, not OpenAI's `seed`.
    let temperature: Double
    let randomSeed: Int

    struct Message: Encodable {
        let role: String
        let content: String
    }

    /// Custom structured output (#174): `{type: "json_schema", json_schema:
    /// {name, schema, strict}}`, the OpenAI-shaped form.
    ///
    /// With `strict` the answer is constrained to the schema rather than only
    /// prompted towards it. Mistral documents no keyword list of its own; the
    /// schema sticks to the subset Claude and Gemini share (`type`,
    /// `properties`, `required`, `enum`, `anyOf`, `items`,
    /// `additionalProperties: false`, `description`), which is also what
    /// Mistral's own SDK generates from a Pydantic model.
    struct ResponseFormat: Encodable {
        let type = "json_schema"
        let jsonSchema: JSONSchema

        struct JSONSchema: Encodable {
            let name: String
            let schema: JSONValue
            let strict: Bool
        }

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, stream, messages, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
        case randomSeed = "random_seed"
    }
}
