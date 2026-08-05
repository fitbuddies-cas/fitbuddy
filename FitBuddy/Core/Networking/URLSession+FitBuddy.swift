import Foundation

extension URLSession {
    /// Shared session for every FitBuddy API call that carries a user API key
    /// (Hevy, Claude).
    ///
    /// Built on `.ephemeral` so nothing touches disk: no URL cache, no cookie
    /// jar, no credential storage. Responses to key-bearing requests therefore
    /// cannot end up in `Library/Caches`, where they would outlive the app
    /// session and sit outside the Keychain's protection class.
    ///
    /// `.shared` is deliberately *not* used: it caches to disk by default and
    /// is process-wide, so any future component could change its behaviour
    /// underneath us.
    static let fitBuddy: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // `.ephemeral` already implies all of the following. They are spelled
        // out anyway so the privacy guarantee is auditable at a glance and a
        // later switch to `.default` cannot silently re-enable disk storage.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()
}
