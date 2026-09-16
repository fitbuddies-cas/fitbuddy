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

    /// Output limits and, since #174, the answer's shape.
    ///
    /// `responseJsonSchema` rather than `responseSchema`: the latter takes
    /// Google's OpenAPI subset (`nullable`, no `additionalProperties`), the
    /// former plain JSON Schema — `type`, `properties`, `required`, `enum`,
    /// `anyOf`, `items`, `additionalProperties`, `description` and the
    /// non-standard `propertyOrdering`, but no `const`. The two fields are
    /// mutually exclusive, and both require `responseMimeType`
    /// `application/json`. Works with `streamGenerateContent`: the chunks'
    /// text concatenates to the JSON document.
    struct GenerationConfig: Encodable {
        let maxOutputTokens: Int
        let responseMimeType: String
        let responseJsonSchema: JSONValue
    }
}
