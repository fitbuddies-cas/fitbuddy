import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// Why a bundled mock payload could not be turned into workouts.
///
/// The first two cases mean the Debug bundle is broken rather than that
/// something went wrong at runtime — the payloads ship with it. The third is a
/// caller's mistake and says so.
enum MockWorkoutError: Error, Equatable {
    /// No `<resource>.json` in the bundle.
    case missingPayload(String)
    /// The payload is not in the wire format its source is read with.
    case invalidPayload(String)
    /// The profile records nothing from this source (#188) — a Hevy page
    /// asked of a Strava-only profile, say. Not a broken bundle: the profile
    /// simply has no such half, and answering with an empty page would claim
    /// it had one and trained nothing.
    case noPayload(profile: String, source: ConnectorSource)
}

#endif
