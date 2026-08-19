import Foundation

/// Builds Claude Messages API SSE bodies in the real wire format, so tests
/// exercise `InferenceService`'s actual parsing path instead of a shortcut.
enum ClaudeSSEFactory {
    /// A complete successful stream: `message_start`, one `content_block_delta`
    /// per entry in `textChunks`, then `content_block_stop` / `message_delta` /
    /// `message_stop` — mirroring what a real analysis response looks like.
    static func body(textChunks: [String]) -> Data {
        var lines: [String] = [
            event("message_start", data: #"{"type":"message_start","message":{"id":"msg_test","type":"message","role":"assistant","content":[],"model":"claude-opus-5"}}"#),
            event("content_block_start", data: #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
        ]
        for chunk in textChunks {
            lines.append(event("content_block_delta", data: deltaPayload(text: chunk)))
        }
        lines.append(event("content_block_stop", data: #"{"type":"content_block_stop","index":0}"#))
        lines.append(event("message_delta", data: #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#))
        lines.append(event("message_stop", data: #"{"type":"message_stop"}"#))
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A stream that answered HTTP 200 but then aborted mid-generation, the
    /// way Claude reports e.g. `overloaded_error` after already starting.
    static func errorBody(type: String, message: String) -> Data {
        let lines = [
            event("message_start", data: #"{"type":"message_start","message":{"id":"msg_test","type":"message","role":"assistant","content":[],"model":"claude-opus-5"}}"#),
            event("content_block_start", data: #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
            event("content_block_delta", data: deltaPayload(text: "Partial")),
            event("error", data: errorPayload(type: type, message: message)),
        ]
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func errorPayload(type: String, message: String) -> String {
        let json = ["type": "error", "error": ["type": type, "message": message]] as [String: Any]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(decoding: data, as: UTF8.self)
    }

    private static func deltaPayload(text: String) -> String {
        let json = ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]] as [String: Any]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(decoding: data, as: UTF8.self)
    }

    private static func event(_ name: String, data: String) -> String {
        "event: \(name)\ndata: \(data)\n"
    }
}
