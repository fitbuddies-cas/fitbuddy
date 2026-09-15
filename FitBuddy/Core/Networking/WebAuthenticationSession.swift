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
///
/// One flow at a time. A second `authenticate` while a sheet is up is refused
/// rather than started: replacing `current` would stop the first session
/// without its completion handler ever running, and the first caller would
/// wait forever.
@MainActor
final class WebAuthenticationSession: NSObject, WebAuthenticating {
    /// Held so it survives the async suspension; `ASWebAuthenticationSession`
    /// stops if nothing retains it.
    private var current: ASWebAuthenticationSession?
    /// The caller waiting on `current`. Resumed exactly once — by the
    /// completion handler, or by `cancelCurrent()` when the calling task is
    /// cancelled before the sheet reports back.
    private var pending: CheckedContinuation<URL, Error>?

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        guard current == nil else { throw WebAuthenticationError.flowAlreadyRunning }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(callbackURLScheme)
                ) { [weak self] callbackURL, error in
                    guard let self else { return }
                    self.current = nil
                    // Already resumed by `cancelCurrent()`: the sheet's late
                    // answer has nobody to go to.
                    guard let pending = self.pending else { return }
                    self.pending = nil
                    if let error {
                        pending.resume(throwing: Self.translate(error))
                    } else if let callbackURL {
                        pending.resume(returning: callbackURL)
                    } else {
                        pending.resume(throwing: URLError(.badServerResponse))
                    }
                }
                session.prefersEphemeralWebBrowserSession = true
                session.presentationContextProvider = self
                current = session
                pending = continuation

                if !session.start() {
                    current = nil
                    pending = nil
                    continuation.resume(throwing: URLError(.cannotConnectToHost))
                }
            }
        } onCancel: {
            // The handler runs on whatever thread cancelled the task; the
            // session and the continuation live on the main actor.
            Task { @MainActor [weak self] in self?.cancelCurrent() }
        }
    }

    /// Dismisses the sheet and lets the waiting caller go with a
    /// `CancellationError`. Idempotent: a session that already reported back
    /// has nothing left to cancel.
    private func cancelCurrent() {
        current?.cancel()
        current = nil
        guard let pending else { return }
        self.pending = nil
        pending.resume(throwing: CancellationError())
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
