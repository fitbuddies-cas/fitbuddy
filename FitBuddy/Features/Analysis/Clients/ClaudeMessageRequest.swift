import Foundation

/// Wire body for a streaming call to Claude's `POST /v1/messages` (#29).
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
