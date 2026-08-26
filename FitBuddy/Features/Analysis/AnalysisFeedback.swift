import Foundation

/// The user's verdict on a finished recommendation — the two buttons under the
/// analysis (US-3 AC9, #32).
///
/// Stays on the device. FitBuddy has no backend to send it to, and a rating
/// leaving the phone would be exactly the kind of transfer the consent screen
/// says does not happen.
enum AnalysisFeedback: String, CaseIterable, Sendable {
    case helpful
    case notHelpful

    /// The button label.
    var label: String {
        switch self {
        case .helpful:
            return "Helpful"
        case .notHelpful:
            return "Not helpful"
        }
    }

    /// The symbol on the button, filled once the verdict is the selected one.
    var symbolName: String {
        switch self {
        case .helpful:
            return "hand.thumbsup"
        case .notHelpful:
            return "hand.thumbsdown"
        }
    }
}
