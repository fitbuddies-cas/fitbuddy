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
        /// The "your saved key was rejected" banner from US-8 AC2.
        static let noticeBanner = "hevyKey.noticeBanner"
    }

    enum LLMKeys {
        static let skipButton = "llmKeys.skipButton"
    }

    enum StravaCredentials {
        static let clientIDField = "stravaCredentials.clientIDField"
        static let clientSecretField = "stravaCredentials.clientSecretField"
        static let saveButton = "stravaCredentials.saveButton"
        static let errorBanner = "stravaCredentials.errorBanner"
    }

    enum StravaConnection {
        static let status = "stravaConnection.status"
        static let connectButton = "stravaConnection.connectButton"
        static let disconnectButton = "stravaConnection.disconnectButton"
        static let credentialsLink = "stravaConnection.credentialsLink"
        static let errorBanner = "stravaConnection.errorBanner"
    }

    enum Dashboard {
        static let root = "dashboard.root"
        static let sessionRow = "dashboard.sessionRow"
        static let exercisesLink = "dashboard.exercisesLink"
        /// The stale-source row from US-8 AC1, with its retry button — one
        /// per source, so two sources gone stale at once stay tellable apart
        /// (#40 review). Takes the raw `ConnectorSource` value rather than the
        /// type: this file is mirrored into the UI-test target, which cannot
        /// see the app module.
        static func staleSource(_ source: String) -> String {
            "dashboard.staleSource." + source
        }
        static let sourceBadge = "dashboard.sourceBadge"
        static let sourceBanner = "dashboard.sourceBanner"
        static let renewalBanner = "dashboard.renewalBanner"
        static let renewButton = "dashboard.renewButton"
    }

    enum WorkoutDetail {
        static let root = "workoutDetail.root"
    }

    enum Exercises {
        static let root = "exercises.root"
        static let row = "exercises.row"
    }

    enum Progression {
        static let root = "progression.root"
        static let chart = "progression.chart"
        static let insufficientData = "progression.insufficientData"
    }
}
