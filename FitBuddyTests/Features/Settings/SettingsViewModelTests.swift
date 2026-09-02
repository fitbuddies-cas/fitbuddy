import XCTest
@testable import FitBuddy

/// Unit tests for `SettingsViewModel` (#83). Keychain access uses the real
/// `KeychainService` on the simulator (same pattern as
/// `LLMKeysViewModelTests`), with all items cleared around each test; the
/// priority order uses an isolated `UserDefaults` suite. The two reset paths
/// are spies — the real services need a SwiftData container and are covered by
/// their own tests.
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var validator: MockHevyKeyValidator!
    private var sessionReset: SessionResetSpy!
    private var dataReset: DataResetSpy!
    private var priority: LLMPriorityStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: SettingsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await clearKeys()
        validator = MockHevyKeyValidator()
        sessionReset = SessionResetSpy()
        dataReset = DataResetSpy()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        priority = LLMPriorityStore(defaults: defaults)
        sut = makeSUT()
    }

    override func tearDown() async throws {
        try await clearKeys()
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        priority = nil
        defaults = nil
        dataReset = nil
        sessionReset = nil
        validator = nil
        keychain = nil
        try await super.tearDown()
    }

    private func makeSUT(keychain override: (any KeychainStoring)? = nil) -> SettingsViewModel {
        SettingsViewModel(
            sessionReset: sessionReset,
            dataReset: dataReset,
            keychain: override ?? keychain,
            validator: validator,
            defaults: defaults
        )
    }

    private func clearKeys() async throws {
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
    }

    // MARK: - Loading

    func testLoadReportsNoKeysOnAFreshDevice() async {
        await sut.load()

        XCTAssertEqual(sut.state, .ready)
        XCTAssertNil(sut.hevyKeyMask)
        XCTAssertEqual(sut.llmKeys, [])
    }

    func testLoadNeverExposesTheStoredKey() async throws {
        try await keychain.save("hv_live_supersecret1234", for: .hevyAPIKey)

        await sut.load()

        let mask = try XCTUnwrap(sut.hevyKeyMask)
        XCTAssertFalse(mask.contains("supersecret"))
        XCTAssertTrue(mask.hasSuffix("1234"))
    }

    func testLoadListsLLMKeysInThePersistedPriorityOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("mistral-abcdefghijkl", for: .mistralAPIKey)
        await priority.save([.mistral, .claude])

        await sut.load()

        XCTAssertEqual(sut.llmKeys.map(\.provider), [.mistral, .claude])
    }

    /// A key the order does not mention must stay visible — an invisible key
    /// is one the user can never delete.
    func testLoadAppendsStoredKeysMissingFromTheOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude])

        await sut.load()

        XCTAssertEqual(sut.llmKeys.map(\.provider), [.claude, .gemini])
    }

    /// Appending is not enough: an appended key that stays outside the
    /// persisted order would never be reached by the fallback chain.
    func testLoadPersistsTheRepairedOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude])

        await sut.load()

        let stored = await priority.order
        XCTAssertEqual(stored, [.claude, .gemini])
    }

    /// The same write drops providers the order still names after their key is
    /// gone — the chain would otherwise point at a provider without a key.
    func testLoadPrunesOrderedProvidersWithoutAStoredKey() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        await priority.save([.claude, .gemini])

        await sut.load()

        let stored = await priority.order
        XCTAssertEqual(stored, [.claude])
    }

    func testLoadIgnoresOrderedProvidersWithoutAStoredKey() async throws {
        await priority.save([.claude, .gemini])

        await sut.load()

        XCTAssertEqual(sut.llmKeys, [])
    }

    func testAddableProvidersExcludeThoseAlreadyStored() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        await sut.load()

        XCTAssertEqual(sut.addableProviders, [.gemini, .mistral])
    }

    func testLoadFailsWhenTheKeychainCannotBeRead() async {
        let failing = makeSUT(keychain: FailingKeychainStub())

        await failing.load()

        XCTAssertEqual(failing.state, .failed)
    }

    // MARK: - Editor

    func testBeginEditingOpensAnEmptyEditor() async throws {
        try await keychain.save("hv_live_abcdefghijkl", for: .hevyAPIKey)
        await sut.load()

        sut.beginEditing(.hevy)

        XCTAssertEqual(sut.editorTarget, .hevy)
        XCTAssertEqual(sut.editorKey, "")
        XCTAssertEqual(sut.editorState, .idle)
        XCTAssertTrue(sut.isReplacing(.hevy))
    }

    func testSubmitEditorValidatesAndStoresTheHevyKey() async throws {
        await sut.load()
        sut.beginEditing(.hevy)
        sut.editorKey = "  hv_live_newkey1234  "

        await sut.submitEditor()

        let received = await validator.receivedKeys
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(received, ["hv_live_newkey1234"])
        XCTAssertEqual(stored, "hv_live_newkey1234")
        XCTAssertNil(sut.editorTarget)
        XCTAssertNotNil(sut.hevyKeyMask)
    }

    func testARejectedHevyKeyIsNeverStored() async throws {
        try await keychain.save("hv_live_oldkey12345", for: .hevyAPIKey)
        await sut.load()
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_rejected1234"

        await sut.submitEditor()

        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(stored, "hv_live_oldkey12345")
        XCTAssertEqual(sut.editorState, .failed(.invalidKey))
        XCTAssertEqual(sut.editorTarget, .hevy)
    }

    func testEditingAfterAFailureClearsTheErrorState() async {
        await sut.load()
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_rejected1234"
        await sut.submitEditor()

        sut.editorKey = "hv_live_rejected12345"

        XCTAssertEqual(sut.editorState, .idle)
    }

    /// US-4: there is no live validation for LLM keys — a wrong one only
    /// surfaces at the next analysis call.
    func testAddingAnLLMKeyStoresItWithoutValidation() async throws {
        await sut.load()
        sut.beginEditing(.llm(.gemini))
        sut.editorKey = "AIzaabcdefghijkl"

        await sut.submitEditor()

        let received = await validator.receivedKeys
        let stored = try await keychain.read(.geminiAPIKey)
        XCTAssertEqual(received, [])
        XCTAssertEqual(stored, "AIzaabcdefghijkl")
        XCTAssertEqual(sut.llmKeys.map(\.provider), [.gemini])
    }

    func testAddingAnLLMKeyAppendsItToThePriorityOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        await priority.save([.claude])
        await sut.load()

        sut.beginEditing(.llm(.mistral))
        sut.editorKey = "mistral-abcdefghijkl"
        await sut.submitEditor()

        let order = await priority.order
        XCTAssertEqual(order, [.claude, .mistral])
    }

    func testReplacingAnLLMKeyKeepsItsPlaceInTheOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("mistral-abcdefghijkl", for: .mistralAPIKey)
        await priority.save([.mistral, .claude])
        await sut.load()

        sut.beginEditing(.llm(.mistral))
        sut.editorKey = "mistral-replacement12"
        await sut.submitEditor()

        let order = await priority.order
        let stored = try await keychain.read(.mistralAPIKey)
        XCTAssertEqual(order, [.mistral, .claude])
        XCTAssertEqual(stored, "mistral-replacement12")
    }

    // MARK: - Replacing the Hevy key (#91)

    /// The cached workouts belong to the previous key. Keeping them would show
    /// one Hevy account's training under another's key — and feed it to the AI
    /// analysis (US-3).
    func testReplacingTheHevyKeyDiscardsTheWorkoutCache() async throws {
        try await keychain.save("hv_live_oldkey12345", for: .hevyAPIKey)
        await sut.load()
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_newkey12345"

        await sut.submitEditor()

        let discards = await sessionReset.discardCount
        let logouts = await sessionReset.hardLogoutCount
        XCTAssertEqual(discards, 1)
        // Replacing is not a logout: the new key stays stored and onboarding
        // is not involved.
        XCTAssertEqual(logouts, 0)
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(stored, "hv_live_newkey12345")
    }

    /// The dashboard sits behind the sheet and its own `.task` does not fire
    /// again on dismiss, so it has to be told the cache is gone.
    func testReplacingTheHevyKeyAsksTheDashboardToReload() async throws {
        try await keychain.save("hv_live_oldkey12345", for: .hevyAPIKey)
        await sut.load()
        var reloads = 0
        sut.onHevyKeyStored = { reloads += 1 }
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_newkey12345"

        await sut.submitEditor()

        XCTAssertEqual(reloads, 1)
    }

    /// Same key entered again: told apart from a real change would mean reading
    /// the stored key back in plaintext, which this screen never does — so the
    /// cache goes, deliberately.
    func testReplacingTheHevyKeyWithTheSameKeyStillDiscardsTheCache() async throws {
        try await keychain.save("hv_live_samekey1234", for: .hevyAPIKey)
        await sut.load()
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_samekey1234"

        await sut.submitEditor()

        let discards = await sessionReset.discardCount
        XCTAssertEqual(discards, 1)
    }

    /// Nothing was stored, so nothing may be thrown away — the user still has
    /// the training data of the key that is still in place.
    func testARejectedHevyKeyKeepsTheWorkoutCache() async throws {
        try await keychain.save("hv_live_oldkey12345", for: .hevyAPIKey)
        await sut.load()
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        var reloads = 0
        sut.onHevyKeyStored = { reloads += 1 }
        sut.beginEditing(.hevy)
        sut.editorKey = "hv_live_rejected1234"

        await sut.submitEditor()

        let discards = await sessionReset.discardCount
        XCTAssertEqual(discards, 0)
        XCTAssertEqual(reloads, 0)
    }

    /// LLM keys have no cache behind them (#91).
    func testStoringAnLLMKeyKeepsTheWorkoutCache() async {
        await sut.load()
        sut.beginEditing(.llm(.gemini))
        sut.editorKey = "AIzaabcdefghijkl"

        await sut.submitEditor()

        let discards = await sessionReset.discardCount
        XCTAssertEqual(discards, 0)
    }

    func testCancelEditingDiscardsTheInput() async {
        await sut.load()
        sut.beginEditing(.llm(.gemini))
        sut.editorKey = "AIzaabcdefghijkl"

        sut.cancelEditing()

        XCTAssertNil(sut.editorTarget)
        XCTAssertEqual(sut.editorKey, "")
    }

    func testCanSubmitEditorNeedsNonEmptyInput() async {
        await sut.load()
        sut.beginEditing(.llm(.gemini))

        XCTAssertFalse(sut.canSubmitEditor)
        sut.editorKey = "   "
        XCTAssertFalse(sut.canSubmitEditor)
        sut.editorKey = "AIzaabcdefghijkl"
        XCTAssertTrue(sut.canSubmitEditor)
    }

    // MARK: - Priority order

    func testMovingAProviderPersistsTheNewOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude, .gemini])
        await sut.load()

        await sut.moveProviders(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let order = await priority.order
        XCTAssertEqual(sut.llmKeys.map(\.provider), [.gemini, .claude])
        XCTAssertEqual(order, [.gemini, .claude])
    }

    func testAReorderSurvivesAColdStart() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude, .gemini])
        await sut.load()
        await sut.moveProviders(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        // A fresh view model sharing the same stores simulates a cold start.
        let relaunched = makeSUT()
        await relaunched.load()

        XCTAssertEqual(relaunched.llmKeys.map(\.provider), [.gemini, .claude])
    }

    // MARK: - Deletion

    func testDeletingAnLLMKeyRemovesItFromTheKeychainAndTheOrder() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude, .gemini])
        await sut.load()

        await sut.delete(.llm(.claude))

        let stored = try await keychain.read(.claudeAPIKey)
        let order = await priority.order
        XCTAssertNil(stored)
        XCTAssertEqual(order, [.gemini])
        XCTAssertEqual(sut.llmKeys.map(\.provider), [.gemini])
    }

    func testDeletingAnLLMKeyKeepsTheOtherProvidersKeys() async throws {
        try await keychain.save("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        try await keychain.save("AIzaabcdefghijkl", for: .geminiAPIKey)
        await priority.save([.claude, .gemini])
        await sut.load()

        await sut.delete(.llm(.claude))

        let stored = try await keychain.read(.geminiAPIKey)
        XCTAssertEqual(stored, "AIzaabcdefghijkl")
    }

    func testDeletingTheHevyKeyRunsTheHardLogoutAndReturnsToOnboarding() async throws {
        try await keychain.save("hv_live_abcdefghijkl", for: .hevyAPIKey)
        await sut.load()
        var returnedToOnboarding = false
        sut.onHevyKeyDeleted = { returnedToOnboarding = true }

        await sut.delete(.hevy)

        let logouts = await sessionReset.hardLogoutCount
        XCTAssertEqual(logouts, 1)
        XCTAssertTrue(returnedToOnboarding)
    }

    func testAFailedLLMDeleteReportsAnErrorAndKeepsTheRow() async throws {
        let stub = InMemoryKeychainStub(failDeletes: true)
        await stub.seed("sk-ant-abcdefghijkl", for: .claudeAPIKey)
        let failing = makeSUT(keychain: stub)
        await priority.save([.claude])
        await failing.load()

        await failing.delete(.llm(.claude))

        XCTAssertNotNil(failing.actionError)
        XCTAssertEqual(failing.llmKeys.map(\.provider), [.claude])
    }

    func testDeleteAllDataWipesEverythingAndReturnsToOnboarding() async {
        await sut.load()
        var returnedToOnboarding = false
        sut.onDataDeleted = { returnedToOnboarding = true }

        await sut.deleteAllData()

        let wipes = await dataReset.deleteCount
        XCTAssertEqual(wipes, 1)
        XCTAssertTrue(returnedToOnboarding)
        XCTAssertFalse(sut.isDeletingAll)
    }
}

// MARK: - Doubles

/// Records how often the hard logout ran.
private actor SessionResetSpy: SessionResetting {
    private(set) var hardLogoutCount = 0
    private(set) var discardCount = 0

    func hardLogout() async {
        hardLogoutCount += 1
    }

    func discardCachedWorkouts() async {
        discardCount += 1
    }
}

/// Records how often the full wipe ran.
private actor DataResetSpy: DataResetting {
    private(set) var deleteCount = 0

    func deleteAllData() async {
        deleteCount += 1
    }
}

/// `KeychainStoring` whose reads always fail — the real `KeychainService`
/// cannot be made to fail on demand on the simulator.
private actor FailingKeychainStub: KeychainStoring {
    func save(_ value: String, for key: KeychainKey) throws {}

    func read(_ key: KeychainKey) throws -> String? { throw KeychainError.invalidData }

    func delete(_ key: KeychainKey) throws {}

    func exists(_ key: KeychainKey) throws -> Bool { false }
}

/// In-memory `KeychainStoring` that can be told to reject deletes.
private actor InMemoryKeychainStub: KeychainStoring {
    private var storedKeys: [KeychainKey: String] = [:]
    private let failDeletes: Bool

    init(failDeletes: Bool) {
        self.failDeletes = failDeletes
    }

    func seed(_ value: String, for key: KeychainKey) {
        storedKeys[key] = value
    }

    func save(_ value: String, for key: KeychainKey) throws { storedKeys[key] = value }

    func read(_ key: KeychainKey) throws -> String? { storedKeys[key] }

    func delete(_ key: KeychainKey) throws {
        guard !failDeletes else { throw KeychainError.invalidData }
        storedKeys[key] = nil
    }

    func exists(_ key: KeychainKey) throws -> Bool { storedKeys[key] != nil }
}
