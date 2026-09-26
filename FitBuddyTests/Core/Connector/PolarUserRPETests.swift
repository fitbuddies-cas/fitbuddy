import XCTest
@testable import FitBuddy

final class PolarUserRPETests: XCTestCase {
    func testEveryKnownPolarLabelMapsOntoItsCase() {
        let expected: [(String, PolarUserRPE)] = [
            ("RPE_NONE", .none),
            ("RPE_VERY_EASY", .veryEasy),
            ("RPE_EASY", .easy),
            ("RPE_MODERATE", .moderate),
            ("RPE_BRISK", .brisk),
            ("RPE_HARD", .hard),
            ("RPE_VERY_HARD", .veryHard),
            ("RPE_EXHAUSTING", .exhausting),
            ("RPE_MAXIMAL", .maximal),
            ("RPE_EXTREME", .extreme),
        ]

        for (label, rating) in expected {
            XCTAssertEqual(PolarUserRPE(polarValue: label), rating, label)
        }
    }

    /// Ten ordered ratings plus the fallback, declared in Polar's order —
    /// the order is the only relation the enum carries, not a number.
    func testTheRatingsAreDeclaredInPolarsOrderFromNoneToExtreme() {
        XCTAssertEqual(PolarUserRPE.allCases.count, 11)
        XCTAssertEqual(PolarUserRPE.allCases.first, PolarUserRPE.none)
        XCTAssertEqual(PolarUserRPE.allCases.dropLast().last, .extreme)
        XCTAssertEqual(PolarUserRPE.allCases.last, .unknown)
    }

    func testAnUnrecognisedLabelDecodesAsUnknownInsteadOfThrowing() throws {
        let decoded = try JSONDecoder().decode([PolarUserRPE].self, from: Data(#"["RPE_NEW", "rpe_hard", "RPE_HARD"]"#.utf8))

        XCTAssertEqual(decoded, [.unknown, .unknown, .hard])
    }

    func testEncodingWritesPolarsLabel() throws {
        let data = try JSONEncoder().encode([PolarUserRPE.brisk])

        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["RPE_BRISK"]"#)
    }
}
