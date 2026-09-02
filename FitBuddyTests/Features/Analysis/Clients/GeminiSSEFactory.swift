import Foundation

/// Builds Gemini `streamGenerateContent?alt=sse` bodies in the real wire
/// format, so tests exercise `GeminiClient`'s actual parsing path instead of a
/// shortcut.
enum GeminiSSEFactory {
    /// A complete successful stream: one chunk per entry in `textChunks`,
    /// with the last one carrying the `finishReason` a real response ends on.
    static func body(textChunks: [String]) -> Data {
        var lines = textChunks.map { line(payload(text: $0, finishReason: nil)) }
        lines.append(line(payload(text: nil, finishReason: "STOP")))
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A chunk whose candidate carries no `parts` at all — Gemini sends these
    /// for safety and usage metadata, and they must not be read as text.
    static func metadataOnlyBody() -> Data {
        Data(line(payload(text: nil, finishReason: "STOP")).utf8)
    }

    /// A stream that answered HTTP 200 and then reported a failure as a frame,
    /// the way Google returns e.g. an exhausted quota mid-generation.
    static func errorBody(status: String, message: String) -> Data {
        let json: [String: Any] = ["error": ["code": 429, "status": status, "message": message]]
        return Data(line(encode(json)).utf8)
    }

    /// A stream whose prompt was rejected by a safety filter: 200, no
    /// candidate, only a `promptFeedback`.
    static func blockedPromptBody(reason: String) -> Data {
        let json: [String: Any] = ["promptFeedback": ["blockReason": reason]]
        return Data(line(encode(json)).utf8)
    }

    /// A stream that produced `textChunks` and then stopped for
    /// `finishReason` rather than reaching the end of its answer.
    static func body(textChunks: [String], finishReason: String) -> Data {
        var lines = textChunks.map { line(payload(text: $0, finishReason: nil)) }
        lines.append(line(payload(text: nil, finishReason: finishReason)))
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func payload(text: String?, finishReason: String?) -> String {
        var candidate: [String: Any] = [:]
        if let text {
            candidate["content"] = ["role": "model", "parts": [["text": text]]]
        }
        if let finishReason {
            candidate["finishReason"] = finishReason
        }
        return encode(["candidates": [candidate]])
    }

    private static func encode(_ json: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(decoding: data, as: UTF8.self)
    }

    private static func line(_ data: String) -> String {
        "data: \(data)\n"
    }
}
