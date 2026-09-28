import XCTest
@testable import FitBuddy

/// `AnalysisValidationLogFormat` (#228): the log survives the trip through
/// the blob, and anything it cannot read comes back as "not recorded".
final class AnalysisValidationLogFormatTests: XCTestCase {
    private let log = AnalysisValidationLog(
        provider: .mistral,
        model: "mistral-medium-3-5",
        modelVerdict: .recover,
        appVerdict: .insufficientData,
        verdictReason: .tooFewSessions,
        interventions: [
            AnalysisIntervention(
                subject: .repProgression,
                action: .downgraded,
                reason: .aboveRepStep,
                figure: AnalysisInterventionFigure(proposed: 9, app: 5, allowed: 6...7, unit: .repetitions)
            ),
            AnalysisIntervention(subject: .recovery, action: .inserted, reason: .recoveryMissing),
            AnalysisIntervention(subject: .note, action: .dropped, reason: .overCardLimit),
            AnalysisIntervention(subject: .headline, action: .replaced, reason: .verdictOverridden),
        ]
    )

    func testALogRoundTrips() throws {
        let json = try XCTUnwrap(AnalysisValidationLogFormat.encode(log))

        XCTAssertEqual(AnalysisValidationLogFormat.decode(json), log)
    }

    func testAnEmptyLogRoundTripsAsEmpty() throws {
        let clean = AnalysisValidationLog(
            modelVerdict: .hold, appVerdict: .hold, verdictReason: .noNewBest, interventions: []
        )
        let json = try XCTUnwrap(AnalysisValidationLogFormat.encode(clean))

        let decoded = AnalysisValidationLogFormat.decode(json)
        XCTAssertEqual(decoded, clean)
        XCTAssertEqual(decoded?.interventions, [])
    }

    func testNoLogIsNoBlob() {
        XCTAssertNil(AnalysisValidationLogFormat.encode(nil))
        XCTAssertNil(AnalysisValidationLogFormat.decode(nil))
    }

    func testBrokenBytesReadAsNotRecorded() {
        XCTAssertNil(AnalysisValidationLogFormat.decode(Data("not json".utf8)))
    }

    /// A reason a newer build added is nothing this one can count.
    func testAnUnknownReasonReadsAsNotRecorded() throws {
        let json = try XCTUnwrap(AnalysisValidationLogFormat.encode(log))
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
            .replacingOccurrences(of: "\"aboveRepStep\"", with: "\"somethingNew\"")

        XCTAssertNil(AnalysisValidationLogFormat.decode(Data(text.utf8)))
    }

    /// The stored shape names its fields, so a blob can be read by eye while
    /// debugging — and carries no text the model wrote.
    func testTheBlobCarriesNamedFieldsOnly() throws {
        let json = try XCTUnwrap(AnalysisValidationLogFormat.encode(log))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            ["provider", "model", "modelVerdict", "appVerdict", "verdictReason", "interventions"]
        )
    }

    func testAttributionAddsTheProviderAndItsModel() {
        let unattributed = AnalysisValidationLog(
            modelVerdict: .hold, appVerdict: .hold, verdictReason: .noNewBest, interventions: []
        )

        let attributed = unattributed.attributed(to: .claude)

        XCTAssertEqual(attributed.provider, .claude)
        XCTAssertEqual(attributed.model, AnthropicClient.model)
        XCTAssertNil(unattributed.attributed(to: nil).model)
    }

    func testEveryProviderNamesItsClientsModel() {
        XCTAssertEqual(LLMProvider.claude.analysisModel, AnthropicClient.model)
        XCTAssertEqual(LLMProvider.gemini.analysisModel, GeminiClient.model)
        XCTAssertEqual(LLMProvider.mistral.analysisModel, MistralClient.model)
    }
}
