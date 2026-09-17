import XCTest
@testable import FitBuddy

/// Unit tests for the mapping from `InferenceServiceError` onto what the
/// analysis screen tells the user (#31, #79).
final class AnalysisFailureTests: XCTestCase {
    private func failure(_ error: InferenceServiceError, provider: LLMProvider? = .claude) -> AnalysisFailure {
        AnalysisFailure(analysisError: error, provider: provider)
    }

    func testMapsKeyErrorsApart() {
        XCTAssertEqual(failure(.missingAPIKey), .missingAPIKey)
        XCTAssertEqual(failure(.unauthorized), .unauthorized(.claude))
        XCTAssertEqual(failure(.keychainUnavailable), .keychainUnavailable)
    }

    func testMapsTransportErrors() {
        XCTAssertEqual(failure(.networkUnavailable), .offline(.claude))
        XCTAssertEqual(failure(.serviceUnavailable), .serviceUnavailable(.claude))
        XCTAssertEqual(
            failure(.rateLimited(retryAfter: 30)),
            .rateLimited(provider: .claude, retryAfter: 30)
        )
    }

    /// A stream a provider aborts after answering 200 is a service problem to
    /// the user, not a new category of failure.
    func testMapsStreamInterruptionOntoServiceUnavailable() {
        XCTAssertEqual(failure(.streamInterrupted(message: "overloaded")), .serviceUnavailable(.claude))
    }

    func testMapsUnreadableResponses() {
        XCTAssertEqual(failure(.invalidResponse), .unreadableResponse(.claude))
        XCTAssertEqual(failure(.unexpectedStatus(418)), .unreadableResponse(.claude))
        XCTAssertEqual(failure(.alreadyInProgress), .unreadableResponse(.claude))
    }

    func testMapsForeignErrorsOntoCacheFailure() {
        struct Boom: Error {}
        XCTAssertEqual(AnalysisFailure(analysisError: Boom()), .cacheUnavailable)
    }

    // MARK: - Naming the provider (#79)

    /// After a fallback the failing provider is not necessarily the one the
    /// user ranked first, so the message has to name the one that actually
    /// failed — "Claude unavailable" after Mistral died would be wrong.
    func testMessagesNameTheProviderTheErrorCameFrom() {
        let failure = AnalysisFailure(analysisError: InferenceServiceError.unauthorized, provider: .mistral)

        XCTAssertTrue(failure.title.contains("Mistral"), failure.title)
        XCTAssertTrue(failure.message.contains("Mistral"), failure.message)
        XCTAssertFalse(failure.message.contains("Claude"), failure.message)
    }

    /// A run that failed before any provider was picked (no key, cache error)
    /// still has to read as a sentence.
    func testFallsBackToANeutralNounWhenNoProviderIsKnown() {
        let failure = AnalysisFailure(analysisError: InferenceServiceError.serviceUnavailable, provider: nil)

        XCTAssertFalse(failure.title.isEmpty)
        XCTAssertTrue(failure.message.contains("The provider"), failure.message)
    }

    /// The one message that must stay provider-free: with three slots
    /// configured and none of them holding a key, naming one would be a guess.
    func testMissingKeyMessageNamesNoProvider() {
        let message = AnalysisFailure.missingAPIKey.message

        for provider in LLMProvider.allCases {
            XCTAssertFalse(message.contains(provider.displayName), message)
        }
    }

    // MARK: - Retry and formatting

    func testKeyAndDataFailuresAreNotRetryable() {
        XCTAssertFalse(AnalysisFailure.missingAPIKey.isRetryable)
        XCTAssertFalse(AnalysisFailure.unauthorized(.claude).isRetryable)
        XCTAssertFalse(AnalysisFailure.noTrainingData.isRetryable)
        XCTAssertTrue(AnalysisFailure.offline(.claude).isRetryable)
        XCTAssertTrue(AnalysisFailure.keychainUnavailable.isRetryable)
    }

    /// Only the missing key sends the user to settings (#207): every other
    /// failure either retries or needs something settings cannot give.
    func testOnlyTheMissingKeyLeadsToSettings() {
        XCTAssertTrue(AnalysisFailure.missingAPIKey.leadsToSettings)
        XCTAssertTrue(AnalysisFailure.missingAPIKey.message.contains("Settings"))
        XCTAssertFalse(AnalysisFailure.unauthorized(.claude).leadsToSettings)
        XCTAssertFalse(AnalysisFailure.keychainUnavailable.leadsToSettings)
        XCTAssertFalse(AnalysisFailure.offline(.claude).leadsToSettings)
        XCTAssertFalse(AnalysisFailure.unreadableResponse(.gemini).leadsToSettings)
        XCTAssertFalse(AnalysisFailure.noTrainingData.leadsToSettings)
    }

    func testRateLimitMessageNamesTheWaitWhenTheProviderSentOne() {
        XCTAssertTrue(AnalysisFailure.rateLimited(provider: .claude, retryAfter: 30).message.hasSuffix("Try again in 30 s."))
        XCTAssertTrue(AnalysisFailure.rateLimited(provider: .claude, retryAfter: 180).message.hasSuffix("Try again in 3 min."))
        XCTAssertTrue(AnalysisFailure.rateLimited(provider: .claude, retryAfter: nil).message.hasSuffix("in a few minutes."))
    }

    func testEveryFailureHasATitleMessageAndSymbol() {
        let failures: [AnalysisFailure] = [
            .missingAPIKey, .keychainUnavailable, .unauthorized(.claude), .offline(.gemini),
            .rateLimited(provider: .mistral, retryAfter: nil), .serviceUnavailable(.claude),
            .noTrainingData,
            .cacheUnavailable, .unreadableResponse(.gemini), .unreadableResponse(nil),
        ]
        for failure in failures {
            XCTAssertFalse(failure.title.isEmpty, "\(failure) has no title")
            XCTAssertFalse(failure.message.isEmpty, "\(failure) has no message")
            XCTAssertFalse(failure.symbolName.isEmpty, "\(failure) has no symbol")
        }
    }
}
