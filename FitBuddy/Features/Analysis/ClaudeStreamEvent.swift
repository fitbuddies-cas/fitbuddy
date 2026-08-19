import Foundation

/// One `data:` payload from Claude's streaming Messages API SSE response.
///
/// Only the fields `InferenceService` needs to extract incremental text are
/// modeled — every other event type (`message_start`, `content_block_stop`,
/// `message_delta`, `message_stop`, `ping`) decodes with `delta` as `nil` and
/// is skipped by the caller.
struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}
