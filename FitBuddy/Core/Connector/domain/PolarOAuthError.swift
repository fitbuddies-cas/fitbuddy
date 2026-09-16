import Foundation

/// Everything that can go wrong in the interactive part of the Polar OAuth
/// flow (ADR-11) — before the code ever reaches the token endpoint, whose own
/// failures already map onto `ConnectorError` (`PolarHTTP.failure`).
///
/// No case carries a token, so any of these can be logged or shown as-is.
enum PolarOAuthError: Error, Equatable, Sendable {
    /// The user dismissed the sheet. Not an error to display.
    case cancelled
    /// The user declined on Polar's authorization page.
    case accessDenied
    /// The callback's `state` is not the one we sent. The callback is not ours.
    case stateMismatch
    /// The callback carried neither a code nor a known error.
    case invalidCallback
    /// The browser sheet could not be presented at all — offline, timeout.
    case transport
}
