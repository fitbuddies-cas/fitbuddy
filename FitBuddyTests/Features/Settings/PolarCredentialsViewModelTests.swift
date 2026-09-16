import XCTest
@testable import FitBuddy

/// Unit tests for `PolarCredentialsViewModel` (ADR-11, BYO-app). The
/// store is the in-memory `StubPolarCredentialStore`, so the Keychain failure
/// path can be exercised as well as the happy one. Mirrors
/// `StravaCredentialsViewModelTests`.
@MainActor
final class PolarCredentialsViewModelTests: XCTestCase {
    private var store: StubPolarCredentialStore!
    private var sut: PolarCredentialsViewModel!

    override func setUp() {
        super.setUp()
        store = StubPolarCredentialStore()
        sut = PolarCredentialsViewModel(store: store)
    }

    override func tearDown() {
        sut = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Input gating

    func testCanSaveRequiresBothFields() {
        XCTAssertFalse(sut.canSave)
        sut.clientID = "client-1"
        XCTAssertFalse(sut.canSave)
        sut.clientSecret = "  \n"
        XCTAssertFalse(sut.canSave, "whitespace-only secret must not count")
        sut.clientSecret = "s3cr3t"
        XCTAssertTrue(sut.canSave)
    }

    func testSaveWithIncompleteInputIsNoOp() async {
        await sut.bootstrap()
        sut.clientID = "client-1"

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
        store = StubPolarCredentialStore(
            clientCredentials: PolarClientCredentials(clientID: "client-1", clientSecret: "abcdefghijklmnop")
        )
        sut = PolarCredentialsViewModel(store: store)

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.hasStoredCredentials)
        XCTAssertEqual(sut.storedClientID, "client-1")
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
        sut.clientID = "client-1"
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
        sut.clientID = "  client-1\n"
        sut.clientSecret = " s3cr3t "

        await sut.save()

        XCTAssertEqual(sut.state, .saved)
        let stored = await store.storedClientCredentials
        XCTAssertEqual(stored, PolarClientCredentials(clientID: "client-1", clientSecret: "s3cr3t"))
        XCTAssertEqual(notified, 1)
        XCTAssertTrue(sut.hasStoredCredentials)
        XCTAssertEqual(sut.storedClientID, "client-1")
    }

    /// AC: a Keychain failure shows the banner and keeps the input, so the
    /// user can simply retry.
    func testKeychainFailureKeepsTheInputAndShowsTheBanner() async {
        await store.setFailWrites(true)
        await sut.bootstrap()
        sut.clientID = "client-1"
        sut.clientSecret = "s3cr3t"

        await sut.save()

        XCTAssertEqual(sut.state, .failed(.keychain))
        XCTAssertEqual(sut.clientID, "client-1")
        XCTAssertEqual(sut.clientSecret, "s3cr3t")
        XCTAssertFalse(sut.hasStoredCredentials)
    }

    func testEditingAfterAFailureReturnsToIdle() async {
        await store.setFailWrites(true)
        await sut.bootstrap()
        sut.clientID = "client-1"
        sut.clientSecret = "s3cr3t"
        await sut.save()
        XCTAssertEqual(sut.state, .failed(.keychain))

        sut.clientSecret = "s3cr3t-fixed"

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Reset

    func testResetClearsEverything() async {
        await sut.bootstrap()
        sut.clientID = "client-1"
        sut.clientSecret = "s3cr3t"
        await sut.save()

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.clientID, "")
        XCTAssertEqual(sut.clientSecret, "")
        XCTAssertFalse(sut.hasStoredCredentials)
    }
}
