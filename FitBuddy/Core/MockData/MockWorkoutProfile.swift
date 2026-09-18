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
/// for recovery first (AC4). The three cross-source profiles (#188) do the
/// same for US-15 — one window of nothing but endurance, one of both
/// disciplines side by side, and one whose overall load calls for recovery
/// although no single source shows it.
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
    /// Strava only: four runs a week for eight weeks — an easy run, a tempo
    /// session, a shake-out run and a long trail run, every other day. The
    /// shake-out run is the one without a heart rate, so the endurance section
    /// has to say how many sessions its mean rests on (US-15 AC7).
    ///
    /// An endurance-only window: the analysis offers no profile choice and
    /// runs as "Endurance" (US-15 AC1), and every figure it reports is in km,
    /// min/km and bpm (AC5).
    case runner
    /// Hevy and Strava: three push/pull/legs sessions and three endurance
    /// sessions a week for eight weeks, two of the endurance sessions on a day
    /// that also carried a lift. Four training days a week, so the week is
    /// dense but never a recovery week — the profile for the cross-source
    /// context line of US-15 AC4 and the week-structure section of AC2.
    case mixed
    /// Hevy, Strava and Polar: six days in a row across all three sources,
    /// then two rest days, on top of seven weeks of three lifts and two
    /// endurance sessions a week.
    ///
    /// No single source shows a recovery week — three lifts, two runs and one
    /// ride — and together they are six of the last seven days, which is what
    /// US-15 AC3 asks the app to catch. The two rest days sit where the
    /// re-anchoring keeps the count at six whatever the time of day, as in
    /// `overreached`.
    case overreachedMixed = "overreached-mixed"

    /// The bundled payloads this profile is built from, in the order they are
    /// cached — one per source, each in that source's wire format (#188).
    var payloads: [MockWorkoutPayload] {
        switch self {
        case .personA, .personB, .progressionReady, .overreached:
            return [MockWorkoutPayload(source: .hevy, resourceName: "mock-workouts-\(rawValue)")]
        case .runner:
            return [MockWorkoutPayload(source: .strava, resourceName: "mock-workouts-runner-strava")]
        case .mixed:
            return [
                MockWorkoutPayload(source: .hevy, resourceName: "mock-workouts-mixed-hevy"),
                MockWorkoutPayload(source: .strava, resourceName: "mock-workouts-mixed-strava"),
            ]
        case .overreachedMixed:
            return [
                MockWorkoutPayload(source: .hevy, resourceName: "mock-workouts-overreached-mixed-hevy"),
                MockWorkoutPayload(source: .strava, resourceName: "mock-workouts-overreached-mixed-strava"),
                MockWorkoutPayload(source: .polar, resourceName: "mock-workouts-overreached-mixed-polar"),
            ]
        }
    }

    /// The Hevy payload of this profile, or `nil` for one that records no
    /// strength training — the file a stubbed `GET /v1/workouts` walk serves.
    var hevyPayload: MockWorkoutPayload? {
        payloads.first { $0.source == .hevy }
    }

    /// Label for preview pickers and debug menus.
    var displayName: String {
        switch self {
        case .personA: return "Person A · 5 sessions/week"
        case .personB: return "Person B · 2 sessions/week"
        case .progressionReady: return "Progression-ready · bench 60 kg × 5"
        case .overreached: return "Overreached · 6 of the last 7 days"
        case .runner: return "Runner · 4 runs/week, Strava only"
        case .mixed: return "Mixed · 3 lifts + 3 endurance sessions/week"
        case .overreachedMixed: return "Overreached mixed · 6 of 7 days, 3 sources"
        }
    }
}

#endif
