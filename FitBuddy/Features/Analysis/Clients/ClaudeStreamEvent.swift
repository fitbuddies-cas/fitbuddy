import Foundation

/// One `data:` payload from Claude's streaming Messages API SSE response.
///
/// Only the fields `InferenceService` needs are modeled: incremental text,
/// and the `error` event Claude can send mid-stream after already answering
/// HTTP 200 (e.g. `overloaded_error`) — every other event type
/// (`message_start`, `content_block_stop`, `message_delta`, `message_stop`,
/// `ping`) decodes with both `delta` and `error` as `nil` and is skipped by
/// the caller.
struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: StreamError?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct StreamError: Decodable {
        let type: String
        let message: String
    }
}
