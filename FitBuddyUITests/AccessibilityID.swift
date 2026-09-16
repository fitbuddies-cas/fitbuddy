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
