import XCTest
@testable import FitBuddy

/// Unit tests for the provider attribution the analysis screen renders (#79).
final class AnalysisAttributionTests: XCTestCase {
    func testASingleAttemptIsNotAFallback() {
        let attribution = AnalysisAttribution(first: .claude)

        XCTAssertEqual(attribution.provider, .claude)
        XCTAssertEqual(attribution.attempted, [.claude])
        XCTAssertFalse(attribution.didFallBack)
        XCTAssertTrue(attribution.failedProviders.isEmpty)
        XCTAssertNil(attribution.fallbackNotice)
    }

    func testTheLastAttemptIsTheAnsweringProvider() {
        var attribution = AnalysisAttribution(first: .claude)
        attribution.append(.gemini)

        XCTAssertEqual(attribution.provider, .gemini)
        XCTAssertEqual(attribution.failedProviders, [.claude])
        XCTAssertTrue(attribution.didFallBack)
    }

    func testNoticeNamesTheFailedProviderAndTheAnsweringOne() {
        var attribution = AnalysisAttribution(first: .claude)
        attribution.append(.gemini)

        XCTAssertEqual(attribution.fallbackNotice, "Claude unavailable — answered by Gemini")
    }

    /// With two failures the notice has to name both: "Claude unavailable"
    /// alone would suggest Gemini was never tried.
    func testNoticeListsEveryFailedProvider() {
        var attribution = AnalysisAttribution(first: .claude)
        attribution.append(.gemini)
        attribution.append(.mistral)

        XCTAssertEqual(attribution.fallbackNotice, "Claude and Gemini unavailable — answered by Mistral")
    }
}
