import Foundation

/// What the connection screen says when the OAuth flow fails (#140).
///
/// A presentation layer over `StravaOAuthError`: the service distinguishes ten
/// outcomes, the user needs to know six things. What matters most is
/// `pointsToCredentials` — a wrong client secret is fixed on a different
/// screen than a revoked token, and the banner has to send the user to the
/// right one.
enum StravaConnectionFailure: Equatable {
    /// The user declined on Strava's consent page.
    case accessDenied
    /// Strava rejected the client ID or secret.
    case invalidClientCredentials
    /// The user authorized without `activity:read_all`.
    case missingScope
    /// The callback or the token document was not what Strava documents —
    /// most likely a callback domain that does not match.
    case invalidResponse
    /// Offline, timeout, DNS.
    case network
    /// The token endpoint answered with a certificate FitBuddy must not
    /// trust (failed pinning, #153) — the network is intercepting TLS.
    case untrustedConnection
    /// Strava answered with an error status.
    case serviceUnavailable
    /// The Keychain refused a read or a write: the pair could not be stored,
    /// the stored one could not be read, or a disconnect could not clear it.
    case keychain

    /// Maps a service error onto the failure the user is shown, or `nil` for
    /// a cancellation — a dismissed sheet is a decision, not a failure.
    init?(_ error: StravaOAuthError) {
        switch error {
        case .cancelled: return nil
        case .accessDenied: self = .accessDenied
        case .invalidClientCredentials: self = .invalidClientCredentials
        case .missingScope: self = .missingScope
        case .stateMismatch, .invalidCallback, .invalidResponse: self = .invalidResponse
        case .transport: self = .network
        case .untrustedConnection: self = .untrustedConnection
        case .unexpectedStatus: self = .serviceUnavailable
        // A refresh token is never involved in a fresh authorization; if the
        // code exchange is rejected as a grant, the callback was not usable.
        case .invalidGrant: self = .invalidResponse
        }
    }

    /// Whether the fix is on the credentials screen rather than a retry.
    var pointsToCredentials: Bool {
        switch self {
        case .invalidClientCredentials, .invalidResponse: return true
        case .accessDenied, .missingScope, .network, .untrustedConnection, .serviceUnavailable, .keychain: return false
        }
    }

    /// Banner headline.
    var title: String {
        switch self {
        case .accessDenied: return "Strava access was declined"
        case .invalidClientCredentials: return "Strava rejected the application credentials"
        case .missingScope: return "Activity access was not granted"
        case .invalidResponse: return "Strava did not send FitBuddy back correctly"
        case .network: return "Could not reach Strava"
        case .untrustedConnection: return "Connection to Strava not trusted"
        case .serviceUnavailable: return "Strava is currently unavailable"
        case .keychain: return "Could not update the Strava connection"
        }
    }

    /// Banner body explaining what the user can do about it.
    var message: String {
        switch self {
        case .accessDenied:
            return "You chose not to authorize FitBuddy. Nothing was stored — connect again whenever you like."
        case .invalidClientCredentials:
            return "The client ID or client secret does not match an application on strava.com. Check both on the credentials screen and try again."
        case .missingScope:
            return "FitBuddy needs permission to read your activities. Connect again and leave “View data about your private activities” ticked."
        case .invalidResponse:
            return "Make sure the Authorization Callback Domain of your Strava application is set to “\(StravaKeyPresentation.callbackDomain)”, then try again."
        case .network:
            return "Check your internet connection and try again."
        case .untrustedConnection:
            return "Something on this network is intercepting the secure connection to Strava. Your credentials were not sent. Switch to another network, for example mobile data, and try again."
        case .serviceUnavailable:
            return "Strava answered with an unexpected error — nothing was rejected. Please try again in a little while."
        case .keychain:
            return "The Keychain on this device refused the request. Make sure the device is unlocked and try again."
        }
    }
}
