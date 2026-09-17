import Foundation
@testable import FitBuddy

/// Builds Mistral chat-completion SSE bodies in the real wire format, so tests
/// exercise `MistralClient`'s actual parsing path instead of a shortcut.
enum MistralSSEFactory {
    /// A complete successful stream: an opening role-only delta, one content
    /// delta per entry in `textChunks`, a closing `finish_reason` chunk, and
    /// the `[DONE]` sentinel.
    static func body(textChunks: [String]) -> Data {
        var lines = [line(payload(role: "assistant", content: nil, finishReason: nil))]
        lines += textChunks.map { line(payload(role: nil, content: $0, finishReason: nil)) }
        lines.append(line(payload(role: nil, content: nil, finishReason: "stop")))
        lines.append("data: [DONE]\n")
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A stream answered with reasoning on: `delta.content` arrives as a chunk
    /// array — a `thinking` chunk, then a `text` chunk — before the plain
    /// string deltas of `textChunks` (#211).
    static func bodyWithThinkingChunks(thinking: String, leadingText: String, textChunks: [String]) -> Data {
        let chunkArray: [[String: Any]] = [
            ["type": "thinking", "thinking": [["type": "text", "text": thinking]]],
            ["type": "text", "text": leadingText]
        ]
        var lines = [line(payload(role: "assistant", content: nil, finishReason: nil))]
        lines.append(line(payload(role: nil, content: chunkArray, finishReason: nil)))
        lines += textChunks.map { line(payload(role: nil, content: $0, finishReason: nil)) }
        lines.append(line(payload(role: nil, content: nil, finishReason: "stop")))
        lines.append("data: [DONE]\n")
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A stream whose `[DONE]` is followed by more text — nothing after the
    /// sentinel may reach the caller.
    static func bodyWithTrailingNoise(textChunks: [String]) -> Data {
        var body = String(decoding: body(textChunks: textChunks), as: UTF8.self)
        body += "\n" + line(payload(role: nil, content: "AFTER-DONE", finishReason: nil))
        return Data(body.utf8)
    }

    /// A stream that answered HTTP 200 and then delivered an OpenAI-shaped
    /// error frame instead of the rest of the answer.
    static func errorBody(type: String, message: String) -> Data {
        let json: [String: Any] = ["error": ["type": type, "message": message]]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return Data(line(String(decoding: data, as: UTF8.self)).utf8)
    }

    /// `content` is a `String` or, with reasoning on, a chunk array.
    private static func payload(role: String?, content: Any?, finishReason: String?) -> String {
        var delta: [String: Any] = [:]
        if let role { delta["role"] = role }
        if let content { delta["content"] = content }
        var choice: [String: Any] = ["index": 0, "delta": delta]
        if let finishReason { choice["finish_reason"] = finishReason }
        let json: [String: Any] = ["id": "cmpl_test", "model": MistralClient.model, "choices": [choice]]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(decoding: data, as: UTF8.self)
    }

    private static func line(_ data: String) -> String {
        "data: \(data)\n"
    }
}
