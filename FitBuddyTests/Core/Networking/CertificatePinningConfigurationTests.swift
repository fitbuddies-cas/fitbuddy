import XCTest
@testable import FitBuddy

/// Guards the `NSPinnedDomains` table in `Info.plist` (#153, ADR-004).
///
/// Pinning itself cannot be unit-tested — `StubURLProtocol` never reaches
/// TLS, and the check happens inside the system's trust evaluation. What can
/// be checked is the table the system reads: every host FitBuddy sends a
/// user secret to is listed, each with at least two root pins so a CA
/// rotation cannot lock every tester out at once, and each pin is a valid
/// SPKI SHA-256. The tests read the built app bundle, so they also prove the
/// hand-written plist survived Xcode's merge with the generated one.
final class CertificatePinningConfigurationTests: XCTestCase {
    /// Every host that carries a user secret (an API key, an OAuth token, a
    /// client secret). `flow.polar.com` and Strava's authorization page are
    /// deliberately absent: they run in `ASWebAuthenticationSession`, which
    /// the app cannot pin.
    private static let pinnedHosts: Set<String> = [
        "api.hevyapp.com",
        "api.anthropic.com",
        "generativelanguage.googleapis.com",
        "api.mistral.ai",
        "www.strava.com",
        "www.polaraccesslink.com",
        "polarremote.com",
    ]

    private var pinnedDomains: [String: Any] {
        get throws {
            let ats = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any],
                "NSAppTransportSecurity missing from the app's Info.plist"
            )
            return try XCTUnwrap(ats["NSPinnedDomains"] as? [String: Any], "NSPinnedDomains missing")
        }
    }

    func testEverySecretBearingHostIsPinned() throws {
        XCTAssertEqual(Set(try pinnedDomains.keys), Self.pinnedHosts)
    }

    func testEveryHostHasAtLeastTwoValidCAPins() throws {
        for (host, entry) in try pinnedDomains {
            let identities = try XCTUnwrap(
                (entry as? [String: Any])?["NSPinnedCAIdentities"] as? [[String: String]],
                "\(host) has no NSPinnedCAIdentities"
            )
            XCTAssertGreaterThanOrEqual(identities.count, 2, "\(host) needs a backup pin")

            let pins = identities.compactMap { $0["SPKI-SHA256-BASE64"] }
            XCTAssertEqual(pins.count, identities.count, "\(host): every entry needs a SPKI-SHA256-BASE64 key")
            XCTAssertEqual(Set(pins).count, pins.count, "\(host): duplicate pin")
            for pin in pins {
                XCTAssertEqual(Data(base64Encoded: pin)?.count, 32, "\(host): \(pin) is not a SHA-256 digest")
            }
        }
    }

    /// The pins are CA pins on purpose: a leaf pin breaks on the next
    /// certificate rotation, which for the CDN-fronted hosts is weeks away.
    func testNoHostUsesLeafPins() throws {
        for (host, entry) in try pinnedDomains {
            XCTAssertNil((entry as? [String: Any])?["NSPinnedLeafIdentities"], "\(host) pins a leaf certificate")
        }
    }

    /// Both Polar hosts and both Cloudflare-fronted hosts share a CA, so
    /// their pin sets must stay identical — a rotation fixed on one and
    /// forgotten on the other would fail only one screen.
    func testHostsBehindTheSameCAShareTheirPins() throws {
        let domains = try pinnedDomains
        func pins(_ host: String) -> Set<String> {
            let identities = (domains[host] as? [String: Any])?["NSPinnedCAIdentities"] as? [[String: String]]
            return Set(identities?.compactMap { $0["SPKI-SHA256-BASE64"] } ?? [])
        }
        XCTAssertEqual(pins("www.polaraccesslink.com"), pins("polarremote.com"))
        XCTAssertEqual(pins("api.anthropic.com"), pins("api.mistral.ai"))
    }
}
