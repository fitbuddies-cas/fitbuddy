import AuthenticationServices
import UIKit

/// `WebAuthenticating` backed by `ASWebAuthenticationSession`.
///
/// Main-actor bound because the session needs a presentation anchor and has to
/// be started from the main thread. It is a class rather than an actor for the
/// same reason: the presentation-context callback is a synchronous delegate
/// method, and `@MainActor` gives it a home without a hop.
///
/// The browser session is ephemeral: no cookies are shared with Safari and none
/// survive the sheet. That is the same stance the app takes with
/// `URLSession.fitBuddy` — nothing key-adjacent outlives the flow. The price is
/// that the user signs in to Strava inside the sheet even if Safari knows them;
/// with refresh tokens that happens once per connection, not per sync.
@MainActor
final class WebAuthenticationSession: NSObject, WebAuthenticating {
    /// Held so it survives the async suspension; `ASWebAuthenticationSession`
    /// stops if nothing retains it.
    private var current: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackURLScheme)
            ) { [weak self] callbackURL, error in
                self?.current = nil
                if let error {
                    continuation.resume(throwing: Self.translate(error))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            current = session

            if !session.start() {
                current = nil
                continuation.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }

    /// A dismissed sheet is a cancellation, which `Error.isCancellation` already
    /// knows how to recognise; everything else stays what the framework said.
    private static func translate(_ error: Error) -> Error {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return CancellationError()
        }
        return error
    }
}

extension WebAuthenticationSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
