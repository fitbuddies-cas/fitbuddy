import Foundation

/// Wire body for a streaming call to Gemini's
/// `models/<model>:streamGenerateContent` (#79).
///
/// Gemini keeps the system prompt out of the conversation rather than as a
/// first message: `systemInstruction` is a sibling of `contents`, not an entry
/// in it.
struct GeminiGenerateContentRequest: Encodable {
    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable {
        /// Omitted for `systemInstruction`, which has no speaker.
        let role: String?
        let parts: [Part]

        struct Part: Encodable {
            let text: String
        }
    }

    struct GenerationConfig: Encodable {
        let maxOutputTokens: Int
    }
}
