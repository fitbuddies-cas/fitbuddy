import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES — which is
// why every file here is named `mock-workouts-*.json`, whichever provider's
// wire format it holds.
#if DEBUG

/// One bundled payload of a mock profile: which provider recorded it, and
/// which file holds it (#188).
///
/// A profile used to be one Hevy file, and `MockWorkoutProfile` named it
/// directly. US-15 analyses strength and endurance together, so a profile that
/// only holds lifts cannot exercise it — and a cardio session written by hand
/// into the cache would prove nothing about the mapping the app actually
/// runs. A profile is therefore a *list* of payloads, one per source, each in
/// that source's own wire format and decoded through that source's DTO.
///
/// The source doubles as the format: a Hevy file is a `{"workouts": [...]}`
/// object, a Strava and a Polar file are the bare arrays their endpoints
/// return. There is no third thing to configure, because a payload in Strava's
/// format that claimed to come from Polar would be a fixture that lies.
struct MockWorkoutPayload: Hashable, Sendable {
    let source: ConnectorSource
    /// Name of the bundled JSON payload (without the `.json` extension).
    let resourceName: String
}

#endif
