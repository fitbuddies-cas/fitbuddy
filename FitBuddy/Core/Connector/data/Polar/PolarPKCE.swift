import CryptoKit
import Foundation

/// One PKCE (RFC 7636) verifier/challenge pair for a single Polar
/// authorization run (ADR-11).
///
/// FitBuddy is a public OAuth client — there is no confidential secret it
/// could send with the token request — so the `code_verifier` is what proves
/// the app that redeems the authorization code is the same one that started
/// the flow. The `verifier` must be kept in memory for the duration of the
/// redirect and passed back to `PolarOAuthClient.exchange`; the `challenge`
/// goes on the authorization URL.
struct PolarPKCE: Equatable, Sendable {
    /// High-entropy random string, 43–128 chars from the unreserved set.
    let verifier: String
    /// `BASE64URL(SHA256(verifier))` — the `S256` method. `plain` is not
    /// offered: it defeats the point when the redirect can be observed.
    let challenge: String
    let method = "S256"

    /// Generates a fresh pair from 32 cryptographically random bytes (the
    /// verifier is their base64url form, 43 chars — comfortably inside the
    /// RFC's 43–128 window).
    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncodedString()
        self.verifier = verifier

        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }

    /// Test seam: build a pair from a known verifier so the derived challenge
    /// can be checked against an independently computed value.
    init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }
}

extension Data {
    /// base64url without padding (RFC 4648 §5) — the encoding PKCE and JWT
    /// use. `Data.base64EncodedString()` is standard base64 (`+` `/` `=`),
    /// which is not URL-safe and would be rejected on the query string.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
