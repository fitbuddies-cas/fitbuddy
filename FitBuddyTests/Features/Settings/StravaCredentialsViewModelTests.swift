import XCTest
@testable import FitBuddy

/// Unit tests for `StravaCredentialsViewModel` (#139, US-5 AC3). The store is
/// the in-memory `StubStravaCredentialStore`, so the Keychain failure path can
/// be exercised as well as the happy one.
@MainActor
final class StravaCredentialsViewModelTests: XCTestCase {
    private var store: StubStravaCredentialStore!
    private var sut: StravaCredentialsViewModel!

    override func setUp() {
        super.setUp()
        store = StubStravaCredentialStore()
        sut = StravaCredentialsViewModel(store: store)
    }

    override func tearDown() {
        sut = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Input gating

    func testCanSaveRequiresBothFields() {
        XCTAssertFalse(sut.canSave)
        sut.clientID = "123456"
        XCTAssertFalse(sut.canSave)
        sut.clientSecret = "  \n"
        XCTAssertFalse(sut.canSave, "whitespace-only secret must not count")
        sut.clientSecret = "s3cr3t"
        XCTAssertTrue(sut.canSave)
    }

    func testSaveWithIncompleteInputIsNoOp() async {
        await sut.bootstrap()
        sut.clientID = "123456"

        await sut.save()

        XCTAssertEqual(sut.state, .idle)
        let stored = await store.storedClientCredentials
        XCTAssertNil(stored)
    }

    // MARK: - Bootstrap

    func testBootstrapWithoutStoredPairIsIdleAndShowsNothing() async {
        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.hasStoredCredentials)
        XCTAssertNil(sut.storedClientID)
        XCTAssertNil(sut.storedSecretMask)
    }

    /// The client ID is public (it is in the browser URL); the secret is only
    /// ever shown masked, and the fields stay empty regardless.
    func testBootstrapWithStoredPairShowsIDAndMaskedSecretButLeavesFieldsEmpty() async {
        store = StubStravaCredentialStore(
            clientCredentials: StravaClientCredentials(clientID: "123456", clientSecret: "abcdefghijklmnop")
        )
        sut = StravaCredentialsViewModel(store: store)

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.hasStoredCredentials)
        XCTAssertEqual(sut.storedClientID, "123456")
        XCTAssertEqual(sut.storedSecretMask, "••••••••mnop")
        XCTAssertEqual(sut.clientID, "")
        XCTAssertEqual(sut.clientSecret, "")
    }

    /// An unreadable Keychain must not block entry — same stance as the Hevy
    /// key screen.
    func testBootstrapFailsOpenWhenTheStoreCannotBeRead() async {
        await store.setFailReads(true)

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.hasStoredCredentials)
    }

    func testBootstrapRunsOnlyOnce() async {
        await sut.bootstrap()
        sut.clientID = "123456"
        sut.clientSecret = "s3cr3t"
        await sut.save()
        XCTAssertEqual(sut.state, .saved)

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .saved, "a second bootstrap must not reset a saved screen")
    }

    // MARK: - Save

    func testSaveStoresTheTrimmedPairAndNotifies() async {
        var notified = 0
        sut.onSaved = { notified += 1 }
        await sut.bootstrap()
        sut.clientID = "  123456\n"
        sut.clientSecret = " s3cr3t "

        await sut.save()

        XCTAssertEqual(sut.state, .saved)
        let stored = await store.storedClientCredentials
        XCTAssertEqual(stored, StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t"))
        XCTAssertEqual(notified, 1)
        XCTAssertTrue(sut.hasStoredCredentials)
        XCTAssertEqual(sut.storedClientID, "123456")
    }

    /// AC: a Keychain failure shows the banner and keeps the input, so the
    /// user can simply retry.
    func testKeychainFailureKeepsTheInputAndShowsTheBanner() async {
        await store.setFailWrites(true)
        await sut.bootstrap()
        sut.clientID = "123456"
        sut.clientSecret = "s3cr3t"

        await sut.save()

        XCTAssertEqual(sut.state, .failed(.keychain))
        XCTAssertEqual(sut.clientID, "123456")
        XCTAssertEqual(sut.clientSecret, "s3cr3t")
        XCTAssertFalse(sut.hasStoredCredentials)
    }

    func testEditingAfterAFailureReturnsToIdle() async {
        await store.setFailWrites(true)
        await sut.bootstrap()
        sut.clientID = "123456"
        sut.clientSecret = "s3cr3t"
        await sut.save()
        XCTAssertEqual(sut.state, .failed(.keychain))

        sut.clientSecret = "s3cr3t-fixed"

        XCTAssertEqual(sut.state, .idle)
    }

    func testAssigningTheSameValueDoesNotClearAFailure() async {
        await store.setFailWrites(true)
        await sut.bootstrap()
        sut.clientID = "123456"
        sut.clientSecret = "s3cr3t"
        await sut.save()

        sut.clientSecret = "s3cr3t"

        XCTAssertEqual(sut.state, .failed(.keychain))
    }

    // MARK: - Reset

    func testResetClearsEverything() async {
        await sut.bootstrap()
        sut.clientID = "123456"
        sut.clientSecret = "s3cr3t"
        await sut.save()

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.clientID, "")
        XCTAssertEqual(sut.clientSecret, "")
        XCTAssertFalse(sut.hasStoredCredentials)
    }
}
