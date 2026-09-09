import XCTest
@testable import FitBuddy

final class PolarPKCETests: XCTestCase {
    /// RFC 7636 Appendix B reference vector — the `S256` transform must match
    /// byte for byte or Polar rejects the token exchange.
    func testChallengeMatchesTheRFC7636ReferenceVector() {
        let pkce = PolarPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testGeneratedVerifierIsURLSafeAndWithinTheRFCLengthWindow() {
        let pkce = PolarPKCE()

        XCTAssertTrue((43...128).contains(pkce.verifier.count))
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))
    }

    func testEachGenerationProducesADistinctPair() {
        XCTAssertNotEqual(PolarPKCE().verifier, PolarPKCE().verifier)
    }

    func testBase64URLEncodingDropsPaddingAndSubstitutesURLUnsafeCharacters() {
        // 0xFB 0xFF encodes to "+/8=" in standard base64.
        let encoded = Data([0xFB, 0xFF]).base64URLEncodedString()

        XCTAssertEqual(encoded, "-_8")
    }
}
