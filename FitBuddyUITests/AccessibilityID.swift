import Foundation

/// Mirror of the app's `Core/Accessibility/AccessibilityID.swift`.
///
/// A UI test drives the app from a separate process and cannot import the app
/// module, so the identifiers exist twice. Keeping them as constants rather
/// than scattered string literals means one place to update per side — and a
/// rename on only one side fails the tests, which is the point.
enum AccessibilityID {
    enum Consent {
        static let acceptToggle = "consent.acceptToggle"
        static let confirmButton = "consent.confirmButton"
    }

    enum HevyKey {
        static let field = "hevyKey.field"
        static let ctaButton = "hevyKey.ctaButton"
        static let errorBanner = "hevyKey.errorBanner"
    }

    enum LLMKeys {
        static let skipButton = "llmKeys.skipButton"
    }

    enum Dashboard {
        static let root = "dashboard.root"
    }
}
