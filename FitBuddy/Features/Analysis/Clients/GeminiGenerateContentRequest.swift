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
    /// `anyOf`, `items`, `additionalProperties`, `description`, but no
    /// `const`. No `propertyOrdering` either: Google documents that keyword
    /// for the OpenAPI subset (and Gemini 2.0), not in the JSON Schema
    /// keyword list, and an unknown keyword risks a 400 for every analysis.
    /// The field order comes from the system prompt, as for Claude and
    /// Mistral. The two fields are
    /// mutually exclusive, and both require `responseMimeType`
    /// `application/json`. Works with `streamGenerateContent`: the chunks'
    /// text concatenates to the JSON document.
    ///
    /// **No sampling fields at all, on purpose (#226).** Gemini runs on its
    /// provider defaults:
    /// - No `seed`: its acceptance on `gemini-3.6-flash` is unverified — the
    ///   live test on 26.09.2026 only returned HTTP 503 (overload). An unknown
    ///   `generationConfig` key would be an HTTP 400 and break the Gemini
    ///   fallback, so it is not sent. Revisit only with a verified live call.
    /// - No `temperature`: Gemini 3 stays at its default 1.0 (see
    ///   `LLMSampling`).
    ///
    /// `GeminiClientTests` asserts that neither key reaches the wire.
    struct GenerationConfig: Encodable {
        let maxOutputTokens: Int
        let responseMimeType: String
        let responseJsonSchema: JSONValue
    }
}
