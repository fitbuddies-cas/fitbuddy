import Foundation

/// Formats counted nouns for the dashboard: `1 set`, `21 sets`.
///
/// Explicit rather than automatic grammar agreement (`^[…](inflect: true)`):
/// that markup resolves through SwiftUI's localisation path but renders
/// literally wherever a string is built outside it, and the repo ships no
/// string catalog that would make the behaviour explicit. The app is
/// English-only for v0, so the rule is one line and always the same one.
enum CountFormatter {
    static func labelled(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}
