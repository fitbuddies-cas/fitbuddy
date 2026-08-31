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

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, stream, messages
        case maxTokens = "max_tokens"
    }
}
