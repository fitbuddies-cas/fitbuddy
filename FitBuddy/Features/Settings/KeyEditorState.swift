import Foundation

/// State of the key editor sheet in Settings (add or replace a stored key).
///
/// Reuses `APIKeyEntryFailure` rather than restating the same four failure
/// modes: the editor is the same "enter an API key" interaction as onboarding
/// step 2, down to the banner copy.
enum KeyEditorState: Equatable {
    /// Waiting for input; nothing in flight.
    case idle
    /// The key is being verified and/or written to the Keychain.
    case validating
    /// The last attempt failed.
    case failed(APIKeyEntryFailure)
}
