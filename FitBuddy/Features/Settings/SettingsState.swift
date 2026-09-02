import Foundation

/// Load state of the settings screen. Only the initial read of the stored
/// credentials can leave the screen unusable — every later action reports its
/// own failure without discarding what is already on screen.
enum SettingsState: Equatable {
    /// Stored keys and the priority order are still being read.
    case loading
    /// Keys resolved; the screen renders its sections.
    case ready
    /// The Keychain could not be read, so the screen cannot say which keys
    /// exist. Kept distinct from "no keys stored" — claiming the latter for a
    /// failed read would invite the user to overwrite keys that are still there.
    case failed
}
