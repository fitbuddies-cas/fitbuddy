import XCTest
@testable import FitBuddy

/// Unit tests for the shared key-entry banner copy (#96). The type's only job
/// is user-facing text for three screens, so the tests guard that every case
/// has usable copy and that the validator mapping stays deliberate.
final class APIKeyEntryFailureTests: XCTestCase {
    private let allFailures: [APIKeyEntryFailure] = [
        .invalidKey, .network, .untrustedConnection, .serviceUnavailable, .keychain,
    ]

    // MARK: - Validator mapping

    /// The mapping exists exactly once (#96): onboarding step 2 and the
    /// settings editor must turn the same HTTP answer into the same banner.
    func testMapsEveryValidatorErrorOntoItsOwnFailure() {
        XCTAssertEqual(APIKeyEntryFailure(.invalidKey), .invalidKey)
        XCTAssertEqual(APIKeyEntryFailure(.transport), .network)
        XCTAssertEqual(APIKeyEntryFailure(.untrustedConnection), .untrustedConnection)
        XCTAssertEqual(APIKeyEntryFailure(.unexpectedStatus(503)), .serviceUnavailable)
    }

    /// A failed certificate check (pinning, #153) must not inherit the
    /// "check your internet" advice — the user has to leave the network.
    func testUntrustedConnectionIsNeverReportedAsANetworkProblem() {
        XCTAssertNotEqual(APIKeyEntryFailure(.untrustedConnection), .network)
        XCTAssertNotEqual(
            APIKeyEntryFailure.untrustedConnection.message(for: "Hevy"),
            APIKeyEntryFailure.network.message(for: "Hevy")
        )
    }

    /// A rejected key is the one case that may not be reported as a transport
    /// problem — the user has to know their key, not their network, is wrong.
    func testRejectedKeyIsNeverReportedAsANetworkProblem() {
        XCTAssertNotEqual(APIKeyEntryFailure(.invalidKey), .network)
    }

    // MARK: - Copy

    func testEveryFailureHasATitleAndMessage() {
        for failure in allFailures {
            XCTAssertFalse(failure.title(for: "Hevy").isEmpty, "\(failure)")
            XCTAssertFalse(failure.message(for: "Hevy").isEmpty, "\(failure)")
        }
    }

    /// Both banner lines are parameterized, so a provider-specific case has to
    /// actually name the provider it was given.
    func testProviderSpecificCopyNamesTheProvider() {
        for failure in [APIKeyEntryFailure.invalidKey, .serviceUnavailable] {
            XCTAssertTrue(failure.title(for: "Claude").contains("Claude"), failure.title(for: "Claude"))
            XCTAssertTrue(failure.message(for: "Claude").contains("Claude"), failure.message(for: "Claude"))
        }
        XCTAssertTrue(APIKeyEntryFailure.network.title(for: "Claude").contains("Claude"))
    }

    /// Storing a key fails on the device, not at the provider — naming one
    /// would point the user at the wrong place.
    func testKeychainCopyNamesNoProvider() {
        XCTAssertFalse(APIKeyEntryFailure.keychain.title(for: "Hevy").contains("Hevy"))
        XCTAssertFalse(APIKeyEntryFailure.keychain.message(for: "Hevy").contains("Hevy"))
    }

    /// Onboarding step 3 writes up to three keys in one go, step 2 and the
    /// settings editor exactly one — the shared banner may commit to neither
    /// number (#111 review).
    func testKeychainCopyCommitsToNoNumberOfKeys() {
        for copy in [APIKeyEntryFailure.keychain.title(), APIKeyEntryFailure.keychain.message()] {
            XCTAssertFalse(copy.lowercased().contains("key "), copy)
            XCTAssertFalse(copy.lowercased().contains("keys"), copy)
        }
    }

    /// Onboarding step 3 saves up to three provider keys at once and passes no
    /// name. Every case still has to read as a sentence, not as a gap.
    func testFallsBackToANeutralNounWithoutAProvider() {
        for failure in allFailures {
            XCTAssertFalse(failure.title().isEmpty, "\(failure)")
            XCTAssertFalse(failure.message().isEmpty, "\(failure)")
            XCTAssertFalse(failure.title().contains("()"), failure.title())
        }
        XCTAssertTrue(APIKeyEntryFailure.invalidKey.title().contains("The provider"))
        XCTAssertTrue(APIKeyEntryFailure.network.title().contains("the provider"))
    }

    /// The fallback sits in three different sentence positions; after a
    /// possessive it must drop its article (#111 review). "Not empty" alone
    /// would pass "in your the provider account".
    func testNeutralFallbackReadsCorrectlyAfterAPossessive() {
        let message = APIKeyEntryFailure.invalidKey.message()
        XCTAssertTrue(message.contains("in your provider account"), message)
        XCTAssertFalse(message.contains("your the"), message)
    }
}
