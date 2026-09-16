import XCTest
@testable import FitBuddy

/// Keeps `AnalysisReportSchema` in step with the `Codable` types it describes,
/// and inside the JSON Schema subset all three providers accept (#174).
final class AnalysisReportSchemaTests: XCTestCase {
    /// Keywords at least one provider rejects or does not know.
    private static let unsupportedKeywords: Set<String> = [
        "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
        "minLength", "maxLength", "pattern", "minItems", "maxItems", "const",
        "oneOf", "propertyOrdering"
    ]

    private func encoded(_ value: JSONValue) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encoded(_ card: AnalysisCard) throws -> [String: Any] {
        let data = try JSONEncoder().encode(card)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func variants() throws -> [[String: Any]] {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let cards = try XCTUnwrap(properties["cards"] as? [String: Any])
        let items = try XCTUnwrap(cards["items"] as? [String: Any])
        return try XCTUnwrap(items["anyOf"] as? [[String: Any]])
    }

    // MARK: - Report

    func testTheReportRequiresExactlyItsFourFields() throws {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])

        XCTAssertEqual(Set(properties.keys), ["headline", "verdict", "cards", "summary"])
        XCTAssertEqual(Set(required), Set(properties.keys))
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testTheVerdictEnumListsEveryVerdict() throws {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let verdict = try XCTUnwrap(properties["verdict"] as? [String: Any])

        XCTAssertEqual(verdict["enum"] as? [String], ["progress", "recover", "hold"])
    }

    /// Encodes the fixture report and checks its keys against the schema, so a
    /// field renamed in Swift cannot silently drift from what the model is
    /// asked to send.
    func testTheReportFixtureUsesExactlyTheSchemaKeys() throws {
        let data = try JSONEncoder().encode(AnalysisReportFixtures.progress)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let schema = try encoded(AnalysisReportSchema.schema)

        XCTAssertEqual(Set(report.keys), Set(try XCTUnwrap(schema["required"] as? [String])))
    }

    // MARK: - Cards

    func testOneVariantPerCardKind() throws {
        let kinds = try variants().map { variant -> [String] in
            let properties = variant["properties"] as? [String: Any]
            let kind = properties?["kind"] as? [String: Any]
            return kind?["enum"] as? [String] ?? []
        }

        XCTAssertEqual(kinds, AnalysisCard.Kind.allCases.map { [$0.rawValue] })
    }

    func testEachVariantRequiresExactlyTheKeysItsCardEncodes() throws {
        let cardsByKind = Dictionary(
            uniqueKeysWithValues: AnalysisReportFixtures.progress.cards.map { ($0.kind.rawValue, $0) }
        )
        XCTAssertEqual(cardsByKind.count, AnalysisCard.Kind.allCases.count, "the fixture must cover every kind")

        for variant in try variants() {
            let properties = try XCTUnwrap(variant["properties"] as? [String: Any])
            let required = try XCTUnwrap(variant["required"] as? [String])
            let kind = try XCTUnwrap((properties["kind"] as? [String: Any])?["enum"] as? [String]).first
            let card = try XCTUnwrap(cardsByKind[kind ?? ""])

            XCTAssertEqual(Set(required), Set(properties.keys), "\(kind ?? "?"): every property is required")
            XCTAssertEqual(Set(try encoded(card).keys), Set(properties.keys), "\(kind ?? "?")")
            XCTAssertEqual(variant["additionalProperties"] as? Bool, false)
        }
    }

    /// Numbers stay numbers in the schema — the screen formats them.
    func testNumericCardFieldsAreNumbers() throws {
        let numeric: Set<String> = ["fromKg", "toKg", "suggestedRestHours", "perWeekA", "perWeekB"]
        for variant in try variants() {
            let properties = try XCTUnwrap(variant["properties"] as? [String: Any])
            for (key, value) in properties {
                let type = (value as? [String: Any])?["type"] as? String
                XCTAssertEqual(type, numeric.contains(key) ? "number" : "string", key)
            }
        }
    }

    // MARK: - Dialect

    func testEveryObjectForbidsAdditionalPropertiesAndNoUnsupportedKeywordIsUsed() throws {
        var objects = 0
        func walk(_ node: Any, path: String) {
            if let array = node as? [Any] {
                for (index, element) in array.enumerated() { walk(element, path: "\(path)[\(index)]") }
                return
            }
            guard let object = node as? [String: Any] else { return }
            if object["type"] as? String == "object" {
                objects += 1
                XCTAssertEqual(object["additionalProperties"] as? Bool, false, path)
            }
            for (key, value) in object {
                // Keys under `properties` are field names, not keywords.
                if path.hasSuffix(".properties") { walk(value, path: "\(path).\(key)"); continue }
                XCTAssertFalse(Self.unsupportedKeywords.contains(key), "\(path).\(key)")
                walk(value, path: "\(path).\(key)")
            }
        }

        walk(try encoded(AnalysisReportSchema.schema), path: "$")

        XCTAssertEqual(objects, 1 + AnalysisCard.Kind.allCases.count)
    }

    /// Gemini gets the declaration order spelled out, because `JSONEncoder`
    /// does not keep it.
    func testGeminiVariantListsThePropertyOrderOfEveryObject() throws {
        let schema = try encoded(AnalysisReportSchema.schema.addingPropertyOrdering())

        XCTAssertEqual(schema["propertyOrdering"] as? [String], ["headline", "verdict", "cards", "summary"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let items = try XCTUnwrap((properties["cards"] as? [String: Any])?["items"] as? [String: Any])
        let progression = try XCTUnwrap((items["anyOf"] as? [[String: Any]])?.first)
        XCTAssertEqual(
            progression["propertyOrdering"] as? [String],
            ["kind", "exercise", "muscleGroup", "fromKg", "toKg", "reasoning"]
        )
    }

    // MARK: - JSONValue

    func testJSONValueEncodesLiteralsAsJSON() throws {
        let value: JSONValue = ["name": "x", "strict": true, "list": ["a", "b"], "nested": ["k": false]]

        let json = try encoded(value)

        XCTAssertEqual(json["name"] as? String, "x")
        XCTAssertEqual(json["strict"] as? Bool, true)
        XCTAssertEqual(json["list"] as? [String], ["a", "b"])
        XCTAssertEqual((json["nested"] as? [String: Any])?["k"] as? Bool, false)
    }
}
