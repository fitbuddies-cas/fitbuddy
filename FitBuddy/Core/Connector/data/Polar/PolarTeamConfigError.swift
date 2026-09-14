import Foundation

/// Thrown by `PolarClientConfiguration.loadFromTeamConfig(bundle:)` (ADR-11,
/// #155) when the Polar partner credentials are missing or still the
/// checked-in placeholder — a clear failure at connect time beats a
/// bundled default that would silently produce `invalid_client` at Polar.
enum PolarTeamConfigError: Error, Equatable {
    /// `PolarTeamConfig.plist` is not in the bundle. Every developer copies
    /// it locally from `PolarTeamConfig.plist.example` (gitignored, #155) —
    /// this fires when that copy was never made.
    case missingConfigFile
    /// The plist exists but a required key is absent or still reads
    /// `REPLACE_ME` — the example file's own placeholder.
    case placeholderNotReplaced(key: String)
}
