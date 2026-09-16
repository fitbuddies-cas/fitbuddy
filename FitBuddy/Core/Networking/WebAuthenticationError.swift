import Foundation

/// What `WebAuthenticationSession` can refuse on its own, before any browser
/// is involved.
enum WebAuthenticationError: Error, Equatable {
    /// A sheet is already up. The first flow keeps running; this call gets
    /// nothing — `StravaOAuthService` reports it as a transport failure, the
    /// same as any other reason the sheet could not be shown.
    case flowAlreadyRunning
}
