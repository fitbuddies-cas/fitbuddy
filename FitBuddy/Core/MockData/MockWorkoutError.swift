import Foundation

/// Why a bundled mock payload could not be turned into workouts.
///
/// Both cases mean the app bundle is broken rather than that something went
/// wrong at runtime — the payloads ship with the binary.
enum MockWorkoutError: Error, Equatable {
    /// No `<resource>.json` in the bundle.
    case missingPayload(String)
    /// The payload is not a Hevy `GET /v1/workouts` page.
    case invalidPayload(String)
}
