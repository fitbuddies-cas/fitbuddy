import Foundation

/// What the connection screen says when the Polar OAuth flow fails (#157).
///
/// A presentation layer over the two error types `PolarConnectionViewModel`
/// can see: `PolarOAuthError` for the interactive part, `ConnectorError` for
/// the token endpoint (`PolarHTTP.failure`) and the credential store. Mirrors
/// `StravaConnectionFailure` (ADR-11 Nachtrag): `pointsToCredentials` sends
/// the user to the application-credentials screen rather than just offering a
/// retry.
enum PolarConnectionFailure: Equatable {
    /// The user declined on Polar's consent page.
    case accessDenied
    /// The callback was not one FitBuddy could trust or parse.
    case invalidResponse
    /// Offline, timeout, DNS.
    case network
    /// Polar rejected the request — a bad client ID/secret or a dead refresh
    /// token look the same from here, so both point at the credentials screen.
    case unauthorized
    /// The pair came back but could not be stored on this device.
    case keychain

    /// Maps an interactive-flow error onto the failure the user is shown, or
    /// `nil` for a cancellation — a dismissed sheet is a decision, not a
    /// failure.
    init?(_ error: PolarOAuthError) {
        switch error {
        case .cancelled: return nil
        case .accessDenied: self = .accessDenied
        case .stateMismatch, .invalidCallback: self = .invalidResponse
        case .transport: self = .network
        }
    }

    /// Maps a token-endpoint or credential-store error.
    init(_ error: ConnectorError) {
        switch error {
        case .unauthorized: self = .unauthorized
        case .networkUnavailable: self = .network
        case .rateLimited, .serviceUnavailable, .invalidResponse, .notImplemented: self = .invalidResponse
        }
    }

    /// Whether the fix is on the credentials screen rather than a retry.
    var pointsToCredentials: Bool {
        switch self {
        case .unauthorized, .invalidResponse: return true
        case .accessDenied, .network, .keychain: return false
        }
    }

    /// Banner headline.
    var title: String {
        switch self {
        case .accessDenied: return "Polar access was declined"
        case .invalidResponse: return "Polar did not send FitBuddy back correctly"
        case .network: return "Could not reach Polar"
        case .unauthorized: return "Polar rejected the connection"
        case .keychain: return "Could not save the Polar connection"
        }
    }

    /// Banner body explaining what the user can do about it.
    var message: String {
        switch self {
        case .accessDenied:
            return "You chose not to authorize FitBuddy. Nothing was stored — connect again whenever you like."
        case .invalidResponse:
            return "Something in the response from Polar did not match what FitBuddy expected. Please try again."
        case .network:
            return "Check your internet connection and try again."
        case .unauthorized:
            return "The client ID or client secret does not match an application on admin.polaraccesslink.com. Check both on the credentials screen and try again."
        case .keychain:
            return "Storing on this device failed. Please try again."
        }
    }
}
