import XCTest
@testable import FitBuddy

/// Unit tests for the mapping from `InferenceServiceError` onto what the
/// analysis screen tells the user (#31).
final class AnalysisFailureTests: XCTestCase {
    private func failure(_ error: InferenceServiceError) -> AnalysisFailure {
        AnalysisFailure(analysisError: error)
    }

    func testMapsKeyErrorsApart() {
        XCTAssertEqual(failure(.missingAPIKey), .missingAPIKey)
        XCTAssertEqual(failure(.unauthorized), .unauthorized)
        XCTAssertEqual(failure(.keychainUnavailable), .keychainUnavailable)
        XCTAssertEqual(
            failure(.providerNotSupportedYet(.gemini)),
            .providerNotSupported(.gemini)
        )
    }

    /// The message has to name the provider — "not supported yet" without it
    /// leaves the user guessing which key is the problem.
    func testUnsupportedProviderIsNamedAndNotRetryable() {
        let failure = AnalysisFailure.providerNotSupported(.gemini)

        XCTAssertTrue(failure.message.contains(LLMProvider.gemini.displayName))
        XCTAssertFalse(failure.isRetryable)
    }

    func testMapsTransportErrors() {
        XCTAssertEqual(failure(.networkUnavailable), .offline)
        XCTAssertEqual(failure(.serviceUnavailable), .serviceUnavailable)
        XCTAssertEqual(failure(.rateLimited(retryAfter: 30)), .rateLimited(retryAfter: 30))
    }

    /// A stream Claude aborts after answering 200 is a service problem to the
    /// user, not a new category of failure.
    func testMapsStreamInterruptionOntoServiceUnavailable() {
        XCTAssertEqual(failure(.streamInterrupted(message: "overloaded")), .serviceUnavailable)
    }

    func testCarriesCooldownInstant() {
        let availableAt = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertEqual(failure(.cooldownActive(availableAt: availableAt)), .cooldownActive(availableAt: availableAt))
    }

    func testMapsUnreadableResponses() {
        XCTAssertEqual(failure(.invalidResponse), .unreadableResponse)
        XCTAssertEqual(failure(.unexpectedStatus(418)), .unreadableResponse)
        XCTAssertEqual(failure(.alreadyInProgress), .unreadableResponse)
    }

    func testMapsForeignErrorsOntoCacheFailure() {
        struct Boom: Error {}
        XCTAssertEqual(AnalysisFailure(analysisError: Boom()), .cacheUnavailable)
    }

    func testKeyAndCooldownFailuresAreNotRetryable() {
        XCTAssertFalse(AnalysisFailure.missingAPIKey.isRetryable)
        XCTAssertFalse(AnalysisFailure.unauthorized.isRetryable)
        XCTAssertFalse(AnalysisFailure.noTrainingData.isRetryable)
        XCTAssertFalse(AnalysisFailure.cooldownActive(availableAt: Date()).isRetryable)
        XCTAssertTrue(AnalysisFailure.offline.isRetryable)
        XCTAssertTrue(AnalysisFailure.keychainUnavailable.isRetryable)
    }

    func testRateLimitMessageNamesTheWaitWhenClaudeSentOne() {
        XCTAssertTrue(AnalysisFailure.rateLimited(retryAfter: 30).message.hasSuffix("Try again in 30 s."))
        XCTAssertTrue(AnalysisFailure.rateLimited(retryAfter: 180).message.hasSuffix("Try again in 3 min."))
        XCTAssertTrue(AnalysisFailure.rateLimited(retryAfter: nil).message.hasSuffix("in a few minutes."))
    }

    func testEveryFailureHasATitleMessageAndSymbol() {
        let failures: [AnalysisFailure] = [
            .missingAPIKey, .keychainUnavailable, .unauthorized, .offline,
            .rateLimited(retryAfter: nil), .serviceUnavailable,
            .cooldownActive(availableAt: Date()), .noTrainingData,
            .cacheUnavailable, .unreadableResponse, .providerNotSupported(.gemini),
        ]
        for failure in failures {
            XCTAssertFalse(failure.title.isEmpty, "\(failure) has no title")
            XCTAssertFalse(failure.message.isEmpty, "\(failure) has no message")
            XCTAssertFalse(failure.symbolName.isEmpty, "\(failure) has no symbol")
        }
    }
}
