import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisSendConfirmationViewModel` (US-3 AC12, #268): the
/// recipient list, the checkbox gate, and the proof it produces.
@MainActor
final class AnalysisSendConfirmationViewModelTests: XCTestCase {
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    private func makeSUT(
        keys: [KeychainKey: String] = [:],
        order: [LLMProvider] = [],
        keychainFails: Bool = false
    ) async -> AnalysisSendConfirmationViewModel {
        let priority = LLMPriorityStore(defaults: defaults)
        await priority.save(order)
        return AnalysisSendConfirmationViewModel(
            keychain: KeyStub(stored: keys, readFails: keychainFails),
            priority: priority,
            consentVersion: "2026-09-16",
            now: { Self.reference }
        )
    }

    // MARK: - Recipients

    /// Only providers with a stored key are recipients, in the order the
    /// user set — the same walk `InferenceService` takes.
    func testProvidersAreTheOnesWithAKeyInPriorityOrder() async {
        let sut = await makeSUT(
            keys: [.claudeAPIKey: "sk-ant-1", .mistralAPIKey: "m-1"],
            order: [.mistral, .gemini, .claude]
        )

        await sut.load()

        XCTAssertEqual(sut.providers, [.mistral, .claude])
        XCTAssertFalse(sut.isLoadingProviders)
        XCTAssertFalse(sut.couldNotReadProviders)
    }

    /// A key outside the stored order still receives the data (#78), so it
    /// is listed — after the ordered ones.
    func testAProviderOutsideTheStoredOrderIsAppended() async {
        let sut = await makeSUT(
            keys: [.geminiAPIKey: "AQ.1", .claudeAPIKey: "sk-ant-1"],
            order: [.gemini]
        )

        await sut.load()

        XCTAssertEqual(sut.providers, [.gemini, .claude])
    }

    /// An empty string is no key: the settings screen never stores one, but
    /// a slot cleared that way must not read as a recipient.
    func testAnEmptyKeyIsNotARecipient() async {
        let sut = await makeSUT(keys: [.claudeAPIKey: ""], order: [.claude])

        await sut.load()

        XCTAssertEqual(sut.providers, [])
    }

    /// A Keychain that cannot be read leaves the list unknown — and a list
    /// the user cannot see is not one they can confirm.
    func testAnUnreadableKeychainBlocksSending() async {
        let sut = await makeSUT(keys: [.claudeAPIKey: "sk-ant-1"], keychainFails: true)

        await sut.load()
        sut.hasConfirmedCheckbox = true

        XCTAssertTrue(sut.couldNotReadProviders)
        XCTAssertEqual(sut.providers, [])
        XCTAssertFalse(sut.canSend)
        XCTAssertNil(sut.confirm())
    }

    // MARK: - Checkbox gate

    func testTheCheckboxStartsEmpty() async {
        let sut = await makeSUT()

        XCTAssertFalse(sut.hasConfirmedCheckbox)
        XCTAssertFalse(sut.canSend)
    }

    func testNothingIsConfirmedWithoutTheCheckbox() async {
        let sut = await makeSUT(keys: [.claudeAPIKey: "sk-ant-1"], order: [.claude])
        await sut.load()

        XCTAssertNil(sut.confirm())
    }

    func testTheCheckboxEnablesSending() async {
        let sut = await makeSUT(keys: [.claudeAPIKey: "sk-ant-1"], order: [.claude])
        await sut.load()

        sut.hasConfirmedCheckbox = true

        XCTAssertTrue(sut.canSend)
    }

    // MARK: - Proof

    /// The confirmation carries when, under which consent, and exactly the
    /// list that was on screen.
    func testTheConfirmationRecordsTimeConsentVersionAndTheListedProviders() async throws {
        let sut = await makeSUT(
            keys: [.claudeAPIKey: "sk-ant-1", .geminiAPIKey: "AQ.1"],
            order: [.gemini, .claude]
        )
        await sut.load()
        sut.hasConfirmedCheckbox = true

        let confirmation = try XCTUnwrap(sut.confirm())

        XCTAssertEqual(confirmation.confirmedAt, Self.reference)
        XCTAssertEqual(confirmation.consentVersion, "2026-09-16")
        XCTAssertEqual(confirmation.providers, [.gemini, .claude])
    }

    /// The categories the sheet lists are the ones the prompt builder sends
    /// — and the note says what never travels.
    func testTheSheetNamesTheDataCategoriesAndWhatIsNotSent() {
        let categories = AnalysisSendConfirmationViewModel.sentDataCategories
        XCTAssertEqual(categories.count, 4)
        XCTAssertTrue(categories.contains { $0.contains("8 weeks") })
        XCTAssertTrue(categories.contains { $0.contains("sets, repetitions and weights") })
        XCTAssertTrue(categories.contains { $0.contains("Strava or Polar") })
        XCTAssertTrue(categories.contains { $0.contains("goal and years of experience") })
        XCTAssertTrue(AnalysisSendConfirmationViewModel.notSentNote.contains("name, e-mail address or any account ID"))
    }
}

/// In-memory `KeychainStoring` whose reads can be made to fail — the real
/// `KeychainService` cannot on the simulator.
private actor KeyStub: KeychainStoring {
    enum Failure: Error { case locked }

    private let stored: [KeychainKey: String]
    private let readFails: Bool

    init(stored: [KeychainKey: String], readFails: Bool) {
        self.stored = stored
        self.readFails = readFails
    }

    func save(_ value: String, for key: KeychainKey) throws {}

    func read(_ key: KeychainKey) throws -> String? {
        if readFails { throw Failure.locked }
        return stored[key]
    }

    func delete(_ key: KeychainKey) throws {}

    func exists(_ key: KeychainKey) throws -> Bool { stored[key] != nil }
}
