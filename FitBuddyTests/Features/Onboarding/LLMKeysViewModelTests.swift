import XCTest
@testable import FitBuddy

/// Unit tests for `LLMKeysViewModel`. Keychain access uses the real
/// `KeychainService` on the simulator (same pattern as
/// `HevyKeyEntryViewModelTests`), with all provider keys cleared around each
/// test; the skip flag and priority order use an isolated `UserDefaults`
/// suite (same pattern as `FirstLaunchResetServiceTests`).
@MainActor
final class LLMKeysViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: LLMKeysViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        for provider in LLMProvider.allCases {
            try await keychain.delete(provider.keychainKey)
        }
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = LLMKeysViewModel(keychain: keychain, defaults: defaults)
    }

    override func tearDown() async throws {
        for provider in LLMProvider.allCases {
            try await keychain.delete(provider.keychainKey)
        }
        sut = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Slot management

    func testStartsWithASingleEmptySlot() {
        XCTAssertEqual(sut.slots.count, 1)
        XCTAssertNil(sut.slots[0].provider)
        XCTAssertEqual(sut.slots[0].key, "")
    }

    func testSelectAssignsProviderToSlot() {
        sut.select(.gemini, forSlot: sut.slots[0].id)
        XCTAssertEqual(sut.slots[0].provider, .gemini)
    }

    func testChangingProviderClearsTheSlotKey() {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"

        sut.select(.mistral, forSlot: sut.slots[0].id)

        XCTAssertEqual(sut.slots[0].provider, .mistral)
        XCTAssertEqual(sut.slots[0].key, "")
    }

    func testReselectingTheSameProviderKeepsTheKey() {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"

        sut.select(.claude, forSlot: sut.slots[0].id)

        XCTAssertEqual(sut.slots[0].key, "sk-ant-abc")
    }

    func testAvailableProvidersExcludeThoseTakenByOtherSlots() {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"
        sut.addSlot()

        let available = sut.availableProviders(for: sut.slots[1])

        XCTAssertEqual(available, [.gemini, .mistral])
        // The first slot keeps its own choice selectable.
        XCTAssertTrue(sut.availableProviders(for: sut.slots[0]).contains(.claude))
    }

    func testCanAddSlotRequiresACompleteLastSlot() {
        XCTAssertFalse(sut.canAddSlot)
        sut.select(.claude, forSlot: sut.slots[0].id)
        XCTAssertFalse(sut.canAddSlot)
        sut.slots[0].key = "sk-ant-abc"
        XCTAssertTrue(sut.canAddSlot)
    }

    func testAddSlotIsCappedAtOneSlotPerProvider() {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "key-1"
        sut.addSlot()
        sut.select(.gemini, forSlot: sut.slots[1].id)
        sut.slots[1].key = "key-2"
        sut.addSlot()
        sut.select(.mistral, forSlot: sut.slots[2].id)
        sut.slots[2].key = "key-3"

        XCTAssertEqual(sut.slots.count, 3)
        XCTAssertFalse(sut.canAddSlot)
        sut.addSlot()
        XCTAssertEqual(sut.slots.count, 3)
    }

    // MARK: - Input gating

    func testCanSaveRequiresACompleteSlot() {
        XCTAssertFalse(sut.canSave)
        sut.select(.claude, forSlot: sut.slots[0].id)
        XCTAssertFalse(sut.canSave)
        sut.slots[0].key = "   \n"
        XCTAssertFalse(sut.canSave)
        sut.slots[0].key = "sk-ant-abc"
        XCTAssertTrue(sut.canSave)
    }

    func testSaveWithoutCompleteSlotIsNoOp() async throws {
        await sut.bootstrap()
        await sut.save()
        XCTAssertEqual(sut.state, .idle)
        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertNil(stored)
    }

    // MARK: - Save (no live validation, unlike Hevy)

    func testSaveStoresTrimmedKeysAndMovesToSaved() async throws {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "  sk-ant-abc\n"
        await sut.save()

        XCTAssertEqual(sut.state, .saved)
        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertEqual(stored, "sk-ant-abc")
    }

    func testSaveStoresEveryCompleteSlotUnderItsProviderKey() async throws {
        sut.select(.gemini, forSlot: sut.slots[0].id)
        sut.slots[0].key = "AIza-abc"
        sut.addSlot()
        sut.select(.mistral, forSlot: sut.slots[1].id)
        sut.slots[1].key = "mistral-abc"

        await sut.save()

        let gemini = try await keychain.read(.geminiAPIKey)
        let mistral = try await keychain.read(.mistralAPIKey)
        let claude = try await keychain.read(.claudeAPIKey)
        XCTAssertEqual(gemini, "AIza-abc")
        XCTAssertEqual(mistral, "mistral-abc")
        XCTAssertNil(claude)
    }

    func testSaveIgnoresIncompleteTrailingSlot() async throws {
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"
        sut.addSlot()

        await sut.save()

        XCTAssertEqual(sut.state, .saved)
        let priority = await LLMPriorityStore(defaults: defaults).order
        XCTAssertEqual(priority, [.claude])
    }

    // MARK: - Priority order

    func testSavePersistsSlotOrderAsPriority() async {
        sut.select(.mistral, forSlot: sut.slots[0].id)
        sut.slots[0].key = "mistral-abc"
        sut.addSlot()
        sut.select(.claude, forSlot: sut.slots[1].id)
        sut.slots[1].key = "sk-ant-abc"

        await sut.save()

        XCTAssertEqual(
            defaults.stringArray(forKey: LLMPriorityStore.priorityOrderKey),
            ["mistral", "claude"]
        )
    }

    // MARK: - Skip (AC2)

    func testSkipMovesToSkippedWithoutStoringAnything() async throws {
        sut.skip()
        XCTAssertEqual(sut.state, .skipped)
        for provider in LLMProvider.allCases {
            let stored = try await keychain.read(provider.keychainKey)
            XCTAssertNil(stored)
        }
    }

    func testSkipPersistsTheDecisionToUserDefaults() {
        sut.skip()
        XCTAssertTrue(defaults.bool(forKey: "fitbuddy.onboarding.llmKeysSkipped"))
    }

    func testSkipPersistsAcrossRelaunch() async {
        sut.skip()

        // A fresh view model sharing the same stores simulates a cold start
        // after the user previously skipped.
        let relaunched = LLMKeysViewModel(keychain: keychain, defaults: defaults)
        await relaunched.bootstrap()

        XCTAssertEqual(relaunched.state, .skipped)
    }

    // MARK: - Save failure (partial write rollback)

    func testFailedSaveRollsBackKeysWrittenBeforeTheFailure() async throws {
        // Fails on the second of three writes: without a rollback the first
        // key would stay in the Keychain with no priority order naming it.
        let failing = FailingKeychainStub(failOnSaveNumber: 2)
        let sut = LLMKeysViewModel(keychain: failing, defaults: defaults)
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"
        sut.addSlot()
        sut.select(.gemini, forSlot: sut.slots[1].id)
        sut.slots[1].key = "AIza-abc"

        await sut.save()

        XCTAssertEqual(sut.state, .failed(.keychain))
        let stored = await failing.storedKeys
        XCTAssertTrue(stored.isEmpty, "partially written keys must not survive a failed save")
    }

    func testFailedSaveDoesNotPersistAPriorityOrder() async {
        let sut = LLMKeysViewModel(keychain: FailingKeychainStub(failOnSaveNumber: 1), defaults: defaults)
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"

        await sut.save()

        XCTAssertEqual(sut.state, .failed(.keychain))
        let priority = await LLMPriorityStore(defaults: defaults).order
        XCTAssertEqual(priority, [])
    }

    func testEditingAfterAFailedSaveClearsTheError() async {
        let sut = LLMKeysViewModel(keychain: FailingKeychainStub(failOnSaveNumber: 1), defaults: defaults)
        sut.select(.claude, forSlot: sut.slots[0].id)
        sut.slots[0].key = "sk-ant-abc"
        await sut.save()

        sut.slots[0].key = "sk-ant-fixed"

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Bootstrap

    func testInitialStateIsUnknownUntilBootstrap() {
        XCTAssertEqual(sut.state, .unknown)
    }

    func testBootstrapMovesToSavedWhenAnyProviderKeyAlreadyStored() async throws {
        try await keychain.save("mistral-existing", for: .mistralAPIKey)
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .saved)
    }

    func testBootstrapMovesToIdleWithoutStoredKeys() async {
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .idle)
    }
}

/// In-memory `KeychainStoring` that throws on the n-th `save` call — the real
/// `KeychainService` cannot be made to fail on demand on the simulator.
private actor FailingKeychainStub: KeychainStoring {
    private(set) var storedKeys: [KeychainKey: String] = [:]
    private let failOnSaveNumber: Int
    private var saveCount = 0

    init(failOnSaveNumber: Int) {
        self.failOnSaveNumber = failOnSaveNumber
    }

    func save(_ value: String, for key: KeychainKey) throws {
        saveCount += 1
        guard saveCount != failOnSaveNumber else { throw KeychainError.invalidData }
        storedKeys[key] = value
    }

    func read(_ key: KeychainKey) throws -> String? { storedKeys[key] }

    func delete(_ key: KeychainKey) throws { storedKeys[key] = nil }

    func exists(_ key: KeychainKey) throws -> Bool { storedKeys[key] != nil }
}
