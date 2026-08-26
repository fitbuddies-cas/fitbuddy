import Foundation

/// One provider/key pair on the LLM key entry screen (US-4, step 3). A slot
/// starts without a provider; the key field appears once one is picked. The
/// slot order is the fallback priority persisted on save.
struct LLMKeySlot: Identifiable, Equatable {
    let id = UUID()
    var provider: LLMProvider?
    var key = ""

    /// Key with surrounding whitespace/newlines removed (pasting often adds a
    /// trailing newline). This is what gets stored.
    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A slot counts toward saving only with both a provider and a key.
    var isComplete: Bool {
        provider != nil && !trimmedKey.isEmpty
    }
}
