import XCTest
@testable import FitBuddy

/// Skelett-Smoke-Test: stellt sicher, dass App-Modul + Test-Target bauen und laufen.
/// Wird ergänzt durch echte Tests ab #19 (KeychainService).
final class SmokeTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(RootView())
    }
}
