import Foundation

/// Stable handles for the elements the UI tests drive (#120).
///
/// Identifiers rather than labels: a UI test that clicks "Confirm and
/// continue" breaks when the copy is reworded, which says nothing about the
/// flow being broken. These names are part of the app's contract with its
/// tests and should be changed as deliberately as a public API.
///
/// The UI test target cannot import the app module — it drives the app from
/// another process — so `FitBuddyUITests` carries a mirror of this file. A
/// rename here without a rename there fails the tests loudly, which is the
/// intended failure mode.
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

    enum TrainingProfile {
        static let root = "trainingProfile.root"
        static let saveButton = "trainingProfile.saveButton"
        static let skipButton = "trainingProfile.skipButton"
        /// Settings only (#191): drops both answers.
        static let removeButton = "trainingProfile.removeButton"
        /// The row in Settings that opens the profile.
        static let settingsRow = "trainingProfile.settingsRow"
        /// One per option, so a test can pick a specific goal rather than a
        /// position in a list that will grow.
        static func goalOption(_ rawValue: String) -> String {
            "trainingProfile.goal." + rawValue
        }
        static func experienceOption(_ rawValue: String) -> String {
            "trainingProfile.experience." + rawValue
        }
    }

    enum LLMKeys {
        static let skipButton = "llmKeys.skipButton"
    }

    enum StravaCredentials {
        static let clientIDField = "stravaCredentials.clientIDField"
        static let clientSecretField = "stravaCredentials.clientSecretField"
        static let saveButton = "stravaCredentials.saveButton"
        static let errorBanner = "stravaCredentials.errorBanner"
        static let setupGuideLink = "stravaCredentials.setupGuideLink"
    }

    enum StravaConnection {
        static let status = "stravaConnection.status"
        static let connectButton = "stravaConnection.connectButton"
        static let disconnectButton = "stravaConnection.disconnectButton"
        static let credentialsLink = "stravaConnection.credentialsLink"
        static let setupGuideLink = "stravaConnection.setupGuideLink"
        static let errorBanner = "stravaConnection.errorBanner"
    }

    enum PolarCredentials {
        static let clientIDField = "polarCredentials.clientIDField"
        static let clientSecretField = "polarCredentials.clientSecretField"
        static let saveButton = "polarCredentials.saveButton"
        static let errorBanner = "polarCredentials.errorBanner"
    }

    enum PolarConnection {
        static let status = "polarConnection.status"
        static let connectButton = "polarConnection.connectButton"
        static let disconnectButton = "polarConnection.disconnectButton"
        static let credentialsLink = "polarConnection.credentialsLink"
        static let errorBanner = "polarConnection.errorBanner"
    }

    enum Dashboard {
        static let root = "dashboard.root"
        /// Every session row carries it — the tests address them by position,
        /// since the point is that a row opens its session, not which one.
        static let sessionRow = "dashboard.sessionRow"
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
        /// The data-basis line over the result: sources, period, profile and
        /// the thin-data warning (US-6, US-15 AC4).
        static let context = "analysis.context"
        /// Every card of a kind carries its kind's identifier — the tests ask
        /// whether a kind is on screen, not which of its cards.
        static let progressionCard = "analysis.progressionCard"
        /// The rep progression card (US-17 AC3, #234).
        static let repProgressionCard = "analysis.repProgressionCard"
        static let recoveryCard = "analysis.recoveryCard"
        static let imbalanceCard = "analysis.imbalanceCard"
        /// The generic metric card and the interference card (US-15, #186).
        static let metricCard = "analysis.metricCard"
        static let interferenceCard = "analysis.interferenceCard"
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
