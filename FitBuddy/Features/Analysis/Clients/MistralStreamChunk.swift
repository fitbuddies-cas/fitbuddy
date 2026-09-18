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
            /// The answer text carried by this delta, whichever wire shape it
            /// arrived in.
            let content: String?

            /// One entry of a chunk-array `content`. Mistral sends `text`
            /// chunks for the answer and `thinking` chunks for the model's
            /// reasoning; only the former is answer text. Both fields are
            /// optional so that an entry without them does not fail the whole
            /// array decode and lose the text chunk beside it.
            private struct ContentChunk: Decodable {
                let type: String?
                let text: String?
            }

            private enum CodingKeys: String, CodingKey {
                case content
            }

            /// With reasoning on, Mistral's `delta.content` is a chunk array
            /// while the model thinks and a plain string once it answers (#211).
            /// The client leaves reasoning at Mistral's default, so both shapes
            /// have to yield the answer. The array is decoded as one value: an
            /// entry whose `text` is not a string still drops the whole delta.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? container.decode(String.self, forKey: .content) {
                    content = text
                } else if let chunks = try? container.decode([ContentChunk].self, forKey: .content) {
                    content = chunks.filter { $0.type == Self.textChunkType }.compactMap(\.text).joined()
                } else {
                    content = nil
                }
            }

            private static let textChunkType = "text"
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
    /// and `length` can both leave an answer behind — for a `length` cut-off,
    /// whether it is still usable is `AnalysisReportParser`'s call; this one
    /// never does.
    private static let errorFinishReason = "error"
}
