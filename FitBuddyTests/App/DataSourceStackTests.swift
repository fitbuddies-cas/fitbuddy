import XCTest
@testable import FitBuddy

/// Unit tests for `DataSourceStack.resolvedPolarMemberID(from:)` (ADR-11):
/// the AccessLink `member-id` has to stay stable across launches.
final class DataSourceStackTests: XCTestCase {
    func testAStoredMemberIDIsReused() async {
        let store = StubPolarCredentialStore(memberID: "member-1")

        let resolved = await DataSourceStack.resolvedPolarMemberID(from: store)

        XCTAssertEqual(resolved, "member-1")
    }

    func testTheFirstLaunchGeneratesAndStoresAnID() async {
        let store = StubPolarCredentialStore()

        let resolved = await DataSourceStack.resolvedPolarMemberID(from: store)

        let stored = await store.storedMemberID
        XCTAssertEqual(stored, resolved)
    }

    /// A locked Keychain may still hold the stable ID: the stand-in for this
    /// launch must not replace it once writes work again.
    func testAnUnreadableKeychainDoesNotReplaceTheStoredID() async {
        let store = StubPolarCredentialStore(memberID: "member-1")
        await store.setFailReads(true)

        let resolved = await DataSourceStack.resolvedPolarMemberID(from: store)

        let stored = await store.storedMemberID
        XCTAssertNotEqual(resolved, "member-1")
        XCTAssertEqual(stored, "member-1")
    }
}
