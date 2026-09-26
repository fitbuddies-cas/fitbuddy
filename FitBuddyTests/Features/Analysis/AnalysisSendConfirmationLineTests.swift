import XCTest
@testable import FitBuddy

/// The "Confirmed on … · sent to …" line of the history detail (#268).
final class AnalysisSendConfirmationLineTests: XCTestCase {
    func testTheLineNamesTheDateAndEveryRecipientInOrder() {
        let confirmation = AnalysisSendConfirmation(
            confirmedAt: Date(timeIntervalSince1970: 1_788_000_000),
            consentVersion: "2026-09-16",
            providers: [.gemini, .claude]
        )

        let line = AnalysisHistoryDetailView.confirmationText(confirmation)

        XCTAssertTrue(line.hasPrefix("Confirmed on "), line)
        XCTAssertTrue(line.hasSuffix(" · sent to Google (Gemini), Anthropic (Claude)"), line)
    }

    /// A run confirmed with no key stored never reaches a provider; the line
    /// must not pretend otherwise.
    func testTheLineSaysSoWhenNoProviderWasConnected() {
        let confirmation = AnalysisSendConfirmation(
            confirmedAt: Date(timeIntervalSince1970: 1_788_000_000),
            consentVersion: "2026-09-16",
            providers: []
        )

        let line = AnalysisHistoryDetailView.confirmationText(confirmation)

        XCTAssertTrue(line.hasSuffix(" · no provider was connected"), line)
    }
}
