import Foundation

/// One `data:` payload from Mistral's streaming chat completion (#79).
///
/// OpenAI-shaped deltas. A chunk carrying only a `finish_reason` decodes with
/// `content` as `nil` and yields no text; the final `data: [DONE]` sentinel is
/// not JSON and is filtered out before decoding.
struct MistralStreamChunk: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let delta: Delta?

        struct Delta: Decodable {
            let content: String?
        }
    }

    /// The incremental text of this chunk, empty when it carries none.
    var text: String {
        (choices ?? []).compactMap(\.delta?.content).joined()
    }
}
