import Foundation

/// One `data:` payload from Gemini's `streamGenerateContent?alt=sse` response.
///
/// Only the fields the analysis needs are modeled. Every chunk is a complete
/// `GenerateContentResponse`, so a chunk carrying only a `finishReason` or
/// usage metadata decodes with an empty `candidates` list of parts and yields
/// no text.
struct GeminiStreamChunk: Decodable {
    let candidates: [Candidate]?

    struct Candidate: Decodable {
        let content: Content?

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
}
