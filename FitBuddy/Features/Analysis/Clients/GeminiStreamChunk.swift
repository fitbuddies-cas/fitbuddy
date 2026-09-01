import Foundation

/// One `data:` payload from Gemini's `streamGenerateContent?alt=sse` response.
///
/// Only the fields the analysis needs are modeled. Every chunk is a complete
/// `GenerateContentResponse`, so a chunk carrying only a `finishReason` or
/// usage metadata decodes with an empty `candidates` list of parts and yields
/// no text.
struct GeminiStreamChunk: Decodable {
    let candidates: [Candidate]?
    /// Present when the call failed after the 200 — Google reports a
    /// mid-stream failure as a normal SSE frame, not as a status code.
    let error: APIError?
    /// Present when the prompt itself was rejected by a safety filter.
    let promptFeedback: PromptFeedback?

    struct APIError: Decodable {
        let message: String?
        let status: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    struct Candidate: Decodable {
        let content: Content?
        /// Why this candidate stopped, once it has.
        let finishReason: String?

        struct Content: Decodable {
            let parts: [Part]?

            struct Part: Decodable {
                let text: String?
            }
        }
    }

    /// The incremental text of this chunk, empty when it carries none.
    ///
    /// Joined across parts rather than taking the first: a chunk may split its
    /// text across several parts, and dropping the rest would silently truncate
    /// the recommendation.
    var text: String {
        (candidates ?? [])
            .compactMap(\.content?.parts)
            .flatMap { $0 }
            .compactMap(\.text)
            .joined()
    }

    /// Why the answer stopped, or `nil` when this chunk does not end it.
    ///
    /// Gemini answers 200 and then reports a failure inside the stream: an
    /// `error` object, a blocked prompt, or a candidate that finished for a
    /// reason other than reaching the end of its answer. None of those carry
    /// text, so without this they would be skipped like any metadata chunk and
    /// the run would end as a silent success instead of falling back.
    var interruption: String? {
        if let message = error?.message { return message }
        if let reason = promptFeedback?.blockReason { return "blocked: \(reason)" }
        guard let reason = (candidates ?? []).compactMap(\.finishReason).first else { return nil }
        return Self.answeredFinishReasons.contains(reason) ? nil : reason
    }

    /// The two ways a candidate ends with an answer behind it. `MAX_TOKENS`
    /// truncates, but what arrived is still the model's own text; anything else
    /// (`SAFETY`, `RECITATION`, `PROHIBITED_CONTENT`, …) means there is none.
    private static let answeredFinishReasons: Set<String> = ["STOP", "MAX_TOKENS"]
}
