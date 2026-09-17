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

    /// Same privacy guarantees as `.fitBuddy`, for calls that stream over a
    /// longer idle window than a plain request/response — the three
    /// `LLMProviderClient`s (NFR: up to ~30s before a response).
    ///
    /// A per-request `URLRequest.timeoutInterval` does not reliably override
    /// `timeoutIntervalForRequest` on the session's configuration (undocumented
    /// which of the two wins), so a request needing a longer idle timeout needs
    /// its own session rather than `.fitBuddy`.
    static let fitBuddyStreaming: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        // 60s, twice the NFR's expected answer time, because this is an *idle*
        // timeout and every provider here reasons before it writes: nothing at
        // all comes down the connection until the model's first token, so the
        // gap this timeout measures is the whole thinking phase, not a stalled
        // transfer. At 30s a provider that thought a little longer than usual
        // was cut off as if the network had died — the analysis then silently
        // fell through to the next provider, which is how a perfectly good key
        // looked permanently "unavailable".
        //
        // Waiting longer costs the user nothing they cannot stop: the screen
        // offers "Cancel analysis" after 30s without a token
        // (`AnalysisViewModel.defaultSlowThreshold`, US-3 AC1), so the decision
        // to keep waiting stays theirs rather than the transport's.
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()
}
