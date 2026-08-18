import Foundation

/// One of the bundled mock training histories used to develop and demo the
/// dashboard (#44) without a live Hevy account.
///
/// The two profiles cover the usage patterns the dashboard has to stay
/// readable for: a dense strength-training week and a minimal one.
enum MockWorkoutProfile: String, CaseIterable, Sendable {
    /// Trains five times a week — push/pull/legs plus an upper-body volume and
    /// a conditioning session, heavy loads, progressive overload across the
    /// 90-day window.
    case personA = "person-a"
    /// Trains twice a week — two full-body sessions at beginner loads, an
    /// occasional weekend session and one week off in the middle of the window.
    case personB = "person-b"

    /// Name of the bundled JSON payload (without the `.json` extension).
    var resourceName: String { "mock-workouts-\(rawValue)" }

    /// Label for preview pickers and debug menus.
    var displayName: String {
        switch self {
        case .personA: return "Person A · 5 sessions/week"
        case .personB: return "Person B · 2 sessions/week"
        }
    }
}
