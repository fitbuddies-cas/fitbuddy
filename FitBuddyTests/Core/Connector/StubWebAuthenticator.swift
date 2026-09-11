import Foundation
@testable import FitBuddy

/// `WebAuthenticating` double that plays Strava's authorization page.
///
/// By default it behaves like a cooperative server: it reads `state` from the
/// URL it was given and echoes it back with a code and the requested scope.
/// Tests override individual parts of the callback (or the whole thing) to
/// exercise each failure path, or make it throw to stand in for a dismissed
/// sheet.
actor StubWebAuthenticator: WebAuthenticating {
    enum Behaviour {
        /// Echo the request's `state`, return `code` and `scope`.
        case succeed(code: String, scope: String?)
        /// Echo the request's `state`, return an `error` query item.
        case fail(error: String)
        /// Return exactly this URL, whatever was asked.
        case callback(URL)
        /// Throw this error.
        case `throw`(Error)
    }

    private(set) var receivedURLs: [URL] = []
    private(set) var receivedSchemes: [String] = []
    private var behaviour: Behaviour

    init(_ behaviour: Behaviour = .succeed(code: "the-code", scope: "read,activity:read_all")) {
        self.behaviour = behaviour
    }

    func set(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        receivedURLs.append(url)
        receivedSchemes.append(callbackURLScheme)

        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value

        switch behaviour {
        case .succeed(let code, let scope):
            var items = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code", value: code)]
            if let scope { items.append(URLQueryItem(name: "scope", value: scope)) }
            return Self.callback(items)
        case .fail(let error):
            return Self.callback([URLQueryItem(name: "state", value: state), URLQueryItem(name: "error", value: error)])
        case .callback(let url):
            return url
        case .throw(let error):
            throw error
        }
    }

    private static func callback(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(string: StravaOAuthService.redirectURI)!
        components.queryItems = items
        return components.url!
    }
}
