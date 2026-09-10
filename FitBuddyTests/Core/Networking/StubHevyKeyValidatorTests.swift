import XCTest
@testable import FitBuddy

/// Unit tests for the stubbed validator (#120): both verdicts have to be the
/// ones the UI tests then assert against.
final class StubHevyKeyValidatorTests: XCTestCase {
    func testAcceptingVerdictReturnsWithoutThrowing() async throws {
        let sut = StubHevyKeyValidator(verdict: .accepts)
        try await sut.validate("hv_live_anything")
    }

    /// `.invalidKey` and not some generic failure: it is what a revoked key
    /// produces, and it is the only failure the entry screen turns into the
    /// "Try again" path.
    func testRejectingVerdictThrowsTheRejectedKeyFailure() async {
        let sut = StubHevyKeyValidator(verdict: .rejects)

        do {
            try await sut.validate("hv_live_anything")
            XCTFail("Expected .invalidKey to be thrown")
        } catch {
            XCTAssertEqual(error as? HevyKeyValidationError, .invalidKey)
        }
    }
}
