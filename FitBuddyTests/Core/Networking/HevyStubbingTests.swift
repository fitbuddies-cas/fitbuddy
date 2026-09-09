import XCTest
@testable import FitBuddy

/// Unit tests for the DEBUG-only launch-argument seam the UI tests rely on
/// (#120). It is small, but it is also the one thing standing between a
/// stubbed test run and a shipped build that talks to nobody: a parser that
/// answered "stub" too eagerly would be a silent outage.
final class HevyStubbingTests: XCTestCase {
    func testIsInactiveWithoutTheArgument() {
        XCTAssertFalse(HevyStubbing.isActive(in: []))
        XCTAssertFalse(HevyStubbing.isActive(in: ["-fbSkipOnboarding"]))
        XCTAssertNil(HevyStubbing.verdict(in: ["-fbSkipOnboarding", "accepts"]))
    }

    func testReadsTheVerdictThatFollowsTheArgument() {
        XCTAssertEqual(HevyStubbing.verdict(in: ["-fbStubHevy", "accepts"]), .accepts)
        XCTAssertEqual(HevyStubbing.verdict(in: ["-fbStubHevy", "rejects"]), .rejects)
        XCTAssertTrue(HevyStubbing.isActive(in: ["-fbStubHevy", "accepts"]))
    }

    /// A typo must not silently stub the app out — the callers read `nil` as
    /// "use the live collaborator".
    func testUnknownVerdictIsNoVerdict() {
        XCTAssertNil(HevyStubbing.verdict(in: ["-fbStubHevy", "maybe"]))
    }

    /// The argument as the last element has no value behind it; reading one
    /// would run off the end.
    func testTrailingArgumentWithoutAValueIsNoVerdict() {
        XCTAssertNil(HevyStubbing.verdict(in: ["-fbStubHevy"]))
    }
}
