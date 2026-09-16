import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// One of the bundled mock training histories used to develop and demo the
/// dashboard (#44) without a live Hevy account.
///
/// Person A and B cover the usage patterns the dashboard has to stay readable
/// for: a dense strength-training week and a minimal one. The two analysis
/// profiles (#179) each reproduce one acceptance criterion of US-14 from real
/// cache data: a lift that is ready for more load (AC2) and a week that calls
/// for recovery first (AC4).
enum MockWorkoutProfile: String, CaseIterable, Sendable {
    /// Trains five times a week — push/pull/legs plus an upper-body volume and
    /// a conditioning session, heavy loads. Twelve whole weeks of the same five
    /// sessions, every exercise progressing across the window, so training
    /// volume per session rises by roughly a tenth from the oldest week to the
    /// newest instead of only per exercise.
    case personA = "person-a"
    /// Trains twice a week — two full-body sessions at beginner loads, an
    /// occasional weekend session and one week off in the middle of the window.
    /// Loads progress like Person A's, but the irregular schedule makes the
    /// weekly volume jump around that trend.
    case personB = "person-b"
    /// Three sessions a week for eight weeks, alternating an upper- and a
    /// lower-body day, every lift progressing. Bench press ends on three
    /// sessions at 60 kg × 5 with every working set at RPE 7 or lower, the
    /// newest at RPE 7 throughout — the clean overload signal of US-14 AC2.
    case progressionReady = "progression-ready"
    /// Seven weeks of push/pull/legs at three sessions a week, then six days in
    /// a row with every working set at RPE 8, 8.5 and 9, and one rest day
    /// before them. Trains on six of the last seven days, so the recovery hint
    /// of US-14 AC4 is mandatory. The rest day sits where the re-anchoring
    /// keeps the count at six whatever the time of day.
    case overreached = "overreached"

    /// Name of the bundled JSON payload (without the `.json` extension).
    var resourceName: String { "mock-workouts-\(rawValue)" }

    /// Label for preview pickers and debug menus.
    var displayName: String {
        switch self {
        case .personA: return "Person A · 5 sessions/week"
        case .personB: return "Person B · 2 sessions/week"
        case .progressionReady: return "Progression-ready · bench 60 kg × 5"
        case .overreached: return "Overreached · 6 of the last 7 days"
        }
    }
}

#endif
