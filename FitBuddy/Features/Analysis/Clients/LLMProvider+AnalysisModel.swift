import Foundation

extension LLMProvider {
    /// The model every analysis call to this provider names — each client's
    /// own constant, so a changed pin is logged as what it is (#228).
    var analysisModel: String {
        switch self {
        case .claude: return AnthropicClient.model
        case .gemini: return GeminiClient.model
        case .mistral: return MistralClient.model
        }
    }
}
