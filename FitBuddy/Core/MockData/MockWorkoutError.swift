import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// Why a bundled mock payload could not be turned into workouts.
///
/// Both cases mean the Debug bundle is broken rather than that something
/// went wrong at runtime — the payloads ship with it.
enum MockWorkoutError: Error, Equatable {
    /// No `<resource>.json` in the bundle.
    case missingPayload(String)
    /// The payload is not a Hevy `GET /v1/workouts` page.
    case invalidPayload(String)
}

#endif
