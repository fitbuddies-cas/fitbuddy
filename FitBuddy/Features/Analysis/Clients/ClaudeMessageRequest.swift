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

    /// How much reasoning the model spends before it answers.
    struct OutputConfig: Encodable {
        let effort: String
    }

    enum CodingKeys: String, CodingKey {
        case model, system, stream, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}
