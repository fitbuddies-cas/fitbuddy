import Foundation

/// What the connection screen says when the Polar OAuth flow fails (#157).
///
/// A presentation layer over the two error types `PolarConnectionViewModel`
/// can see: `PolarOAuthError` for the interactive part, `ConnectorError` for
/// the token endpoint (`PolarHTTP.failure`) and the credential store.
enum PolarConnectionFailure: Equatable {
    /// The user declined on Polar's consent page.
    case accessDenied
    /// The callback was not one FitBuddy could trust or parse.
    case invalidResponse
    /// Offline, timeout, DNS.
    case network
    /// Polar answered with an error status, or rejected the exchange.
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
            return "Polar rejected the request. Please try connecting again."
        case .keychain:
            return "Storing on this device failed. Please try again."
        }
    }
}
