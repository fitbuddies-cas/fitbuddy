import XCTest
@testable import FitBuddy

/// Skelett-Smoke-Test: Test-Target ist mit dem App-Modul verdrahtet und die
/// Root-View lässt sich zur Laufzeit konstruieren. Wird durch echte Tests ab
/// #19 (KeychainService) ersetzt.
final class SmokeTests: XCTestCase {
    @MainActor
    func testRootViewBodyEvaluates() {
        // Evaluiert den View-Body zur Laufzeit (mehr als ein reiner Compile-Check).
        _ = RootView().body
    }
}
