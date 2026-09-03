import Foundation

/// Renders a stored API key for display. Keys are never shown in plaintext
/// (#83): the user only needs to tell two keys apart, which the last four
/// characters do.
enum KeyMask {
    /// Fixed-width bullet run — deliberately not proportional to the key, so
    /// the mask does not leak its length.
    private static let bullets = String(repeating: "•", count: 8)

    /// Shortest key whose last four characters may be shown. Below that the
    /// tail would give away too large a share of the key, so it is hidden
    /// entirely.
    private static let minimumRevealLength = 12

    static func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumRevealLength else { return bullets }
        return bullets + trimmed.suffix(4)
    }
}
