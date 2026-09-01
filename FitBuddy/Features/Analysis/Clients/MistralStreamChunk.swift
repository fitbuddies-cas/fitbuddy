import Foundation

/// One `data:` payload from Mistral's streaming chat completion (#79).
///
/// OpenAI-shaped deltas. A chunk carrying only a `finish_reason` decodes with
/// `content` as `nil` and yields no text; the final `data: [DONE]` sentinel is
/// not JSON and is filtered out before decoding.
struct MistralStreamChunk: Decodable {
    let choices: [Choice]?
    /// Present when the call failed after the 200 — the OpenAI-shaped error
    /// frame arrives as a normal `data:` line, not as a status code.
    let error: APIError?

    struct APIError: Decodable {
        let message: String?
        let type: String?
    }

    struct Choice: Decodable {
        let delta: Delta?
        /// Why this choice stopped, once it has.
        let finishReason: String?

        struct Delta: Decodable {
            let content: String?
        }

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    /// The incremental text of this chunk, empty when it carries none.
    var text: String {
        (choices ?? []).compactMap(\.delta?.content).joined()
    }

    /// Why the answer stopped, or `nil` when this chunk does not end it.
    ///
    /// Same gap as Gemini's: a failure after the 200 is a `data:` line like any
    /// other, carries no content, and would otherwise be skipped — ending the
    /// run as a silent success instead of falling back to the next provider.
    var interruption: String? {
        if let message = error?.message { return message }
        guard (choices ?? []).contains(where: { $0.finishReason == Self.errorFinishReason }) else { return nil }
        return Self.errorFinishReason
    }

    /// The `finish_reason` Mistral uses when generation itself failed. `stop`
    /// and `length` both leave an answer behind; this one does not.
    private static let errorFinishReason = "error"
}
