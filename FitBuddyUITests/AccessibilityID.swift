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
        /// Every exercise card carries it — each one opens that movement's
        /// statistics (#162).
        static let exerciseCard = "workoutDetail.exerciseCard"
    }

    enum Exercises {
        static let root = "exercises.root"
        static let row = "exercises.row"
    }

    enum Progression {
        static let root = "progression.root"
        static let chart = "progression.chart"
        static let insufficientData = "progression.insufficientData"
        static let unavailable = "progression.unavailable"
        /// The session history under the curve, and its rows (#163).
        static let history = "progression.history"
        static let historyRow = "progression.historyRow"
        /// A set row inside an opened session — present only while that
        /// session is expanded.
        static let historySet = "progression.historySet"
    }

    /// The analysis result, live or from the history (US-14, #177).
    enum Analysis {
        /// The finished recommendation — report or prose, live or restored.
        static let result = "analysis.result"
        static let headline = "analysis.headline"
        /// Every card of a kind carries its kind's identifier — the tests ask
        /// whether a kind is on screen, not which of its cards.
        static let progressionCard = "analysis.progressionCard"
        static let recoveryCard = "analysis.recoveryCard"
        static let imbalanceCard = "analysis.imbalanceCard"
        static let noteCard = "analysis.noteCard"
        /// The prose card of an answer that is not a report (US-14 AC5/AC6).
        static let prose = "analysis.prose"
        /// The short takeaway under the context line (#170).
        static let lead = "analysis.lead"
        /// The "Show full analysis" / "Hide full analysis" button (#170).
        static let fullAnalysisToggle = "analysis.fullAnalysisToggle"
        /// The report's summary, present only while the disclosure is open.
        static let fullAnalysis = "analysis.fullAnalysis"
    }
}
