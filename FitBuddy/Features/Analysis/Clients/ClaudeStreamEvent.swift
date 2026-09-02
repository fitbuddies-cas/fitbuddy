import Foundation

/// One `data:` payload from Claude's streaming Messages API SSE response.
///
/// Only the fields `InferenceService` needs are modeled: incremental text, the
/// `stop_reason` the `message_delta` event carries, and the `error` event
/// Claude can send mid-stream after already answering HTTP 200 (e.g.
/// `overloaded_error`) — every other event type (`message_start`,
/// `content_block_stop`, `message_stop`, `ping`) decodes with `delta` and
/// `error` as `nil` and is skipped by the caller.
struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: StreamError?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        /// Present on `message_delta` only, and the only place a stream says
        /// *why* it ended. Without it a response cut off at `max_tokens` is
        /// indistinguishable from a complete one.
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case stopReason = "stop_reason"
        }
    }

    struct StreamError: Decodable {
        let type: String
        let message: String
    }
}
