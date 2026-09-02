import XCTest
@testable import FitBuddy

/// Unit tests for `KeyMask` — the rendering that keeps stored keys off the
/// settings screen in plaintext (#83).
final class KeyMaskTests: XCTestCase {
    func testMaskRevealsOnlyTheLastFourCharacters() {
        let masked = KeyMask.masked("hv_live_supersecret1234")
        XCTAssertEqual(masked, "••••••••1234")
    }

    /// A short key would give away too large a share of itself, so nothing is
    /// revealed.
    func testShortKeysAreHiddenEntirely() {
        XCTAssertEqual(KeyMask.masked("short1234"), "••••••••")
    }

    /// The bullet run is fixed-width on purpose — a proportional one would
    /// leak the key length.
    func testMaskLengthDoesNotDependOnTheKeyLength() {
        let short = KeyMask.masked(String(repeating: "a", count: 20) + "1234")
        let long = KeyMask.masked(String(repeating: "a", count: 200) + "1234")
        XCTAssertEqual(short.count, long.count)
    }

    func testMaskIgnoresSurroundingWhitespace() {
        XCTAssertEqual(KeyMask.masked("  hv_live_supersecret1234\n"), "••••••••1234")
    }
}
