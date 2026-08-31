import Foundation

/// Wire body for a streaming call to Claude's `POST /v1/messages` (#29).
struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let stream: Bool
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, system, stream, messages
        case maxTokens = "max_tokens"
    }
}
