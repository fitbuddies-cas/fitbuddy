import XCTest
@testable import FitBuddy

/// Unit tests for the shared key-entry banner copy (#96). The type's only job
/// is user-facing text for three screens, so the tests guard that every case
/// has usable copy and that the validator mapping stays deliberate.
final class APIKeyEntryFailureTests: XCTestCase {
    private let allFailures: [APIKeyEntryFailure] = [.invalidKey, .network, .serviceUnavailable, .keychain]

    // MARK: - Validator mapping

    /// The mapping exists exactly once (#96): onboarding step 2 and the
    /// settings editor must turn the same HTTP answer into the same banner.
    func testMapsEveryValidatorErrorOntoItsOwnFailure() {
        XCTAssertEqual(APIKeyEntryFailure(.invalidKey), .invalidKey)
        XCTAssertEqual(APIKeyEntryFailure(.transport), .network)
        XCTAssertEqual(APIKeyEntryFailure(.unexpectedStatus(503)), .serviceUnavailable)
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
}
