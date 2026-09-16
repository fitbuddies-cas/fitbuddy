import Foundation

/// Runs a browser-based authorization and hands back the callback URL.
///
/// The only production conformer wraps `ASWebAuthenticationSession`, which has
/// to be driven from the main actor and cannot run under XCTest. Putting it
/// behind this seam keeps `StravaOAuthService` an `actor` that a test can feed
/// any callback URL it likes.
protocol WebAuthenticating: Sendable {
    /// Presents `url` and resolves once the page redirects to
    /// `callbackURLScheme`. Throws `CancellationError` when the user dismisses
    /// the sheet — a deliberate exit, not a failure.
    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL
}
