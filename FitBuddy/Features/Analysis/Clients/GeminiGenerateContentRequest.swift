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
        let thinkingConfig: ThinkingConfig

        /// How much the model reasons before it answers. Sent explicitly
        /// because the default is not "off": on a Gemini 3 flash model
        /// thinking is always on, and its tokens are drawn from
        /// `maxOutputTokens`.
        struct ThinkingConfig: Encodable {
            let thinkingLevel: String
        }
    }
}
