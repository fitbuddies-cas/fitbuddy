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

    enum PolarConnection {
        static let status = "polarConnection.status"
        static let connectButton = "polarConnection.connectButton"
        static let disconnectButton = "polarConnection.disconnectButton"
        static let errorBanner = "polarConnection.errorBanner"
    }

    enum Dashboard {
        static let root = "dashboard.root"
        /// Every session row carries it — the tests address them by position,
        /// since the point is that a row opens its session, not which one.
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
}
