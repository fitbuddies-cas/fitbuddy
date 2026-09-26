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

    func testTheReportRequiresExactlyItsFiveFields() throws {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])

        XCTAssertEqual(Set(properties.keys), ["headline", "verdict", "lead", "cards", "summary"])
        XCTAssertEqual(Set(required), Set(properties.keys))
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testTheVerdictEnumListsEveryVerdict() throws {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let verdict = try XCTUnwrap(properties["verdict"] as? [String: Any])

        XCTAssertEqual(verdict["enum"] as? [String], ["progress", "recover", "hold"])
    }

    /// ADR-014 §7: the fourth class is a statement the app makes about its own
    /// data basis, so it is never on the list the model chooses from.
    func testTheVerdictEnumDoesNotOfferTheAppsFourthClass() throws {
        let schema = try encoded(AnalysisReportSchema.schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let verdict = try XCTUnwrap(properties["verdict"] as? [String: Any])

        XCTAssertFalse(
            (verdict["enum"] as? [String] ?? []).contains(AnalysisVerdict.insufficientData.rawValue)
        )
        XCTAssertFalse(AnalysisVerdict.modelChoices.contains(.insufficientData))
    }

    /// Encodes the fixture report and checks its keys against the schema, so a
    /// field renamed in Swift cannot silently drift from what the model is
    /// asked to send.
    func testTheReportFixtureUsesExactlyTheSchemaKeys() throws {
        let data = try JSONEncoder().encode(AnalysisReportFactory.progress)
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
            uniqueKeysWithValues: AnalysisReportFactory.progress.cards.map { ($0.kind.rawValue, $0) }
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

    /// Numbers stay numbers in the schema — the screen formats them. A day
    /// count is an `integer`, because the card decodes it as one and 3.0 days
    /// would fail to decode (#186).
    func testNumericCardFieldsAreNumbers() throws {
        let numeric: Set<String> = ["fromKg", "toKg", "weightKg", "suggestedRestHours", "perWeekA", "perWeekB", "from", "to"]
        let integers: Set<String> = ["strengthDays", "cardioDays", "overlapDays", "fromReps", "toReps"]
        for variant in try variants() {
            let properties = try XCTUnwrap(variant["properties"] as? [String: Any])
            for (key, value) in properties {
                let type = (value as? [String: Any])?["type"] as? String
                let expected = numeric.contains(key) ? "number" : integers.contains(key) ? "integer" : "string"
                XCTAssertEqual(type, expected, key)
            }
        }
    }

    /// The unit of a metric card is one of the schema's two enum-valued
    /// properties, next to `verdict`. It lists every `MetricUnit` the model
    /// may state — a case added to the enum and left out of the schema would
    /// be one the model can never use (#186).
    ///
    /// `beatsPerMinute` is deliberately not among them: see
    /// `testTheUnitEnumOffersNoHeartRate`.
    func testTheUnitEnumListsEveryMetricUnit() throws {
        let variant = try XCTUnwrap(
            try variants().first {
                let properties = $0["properties"] as? [String: Any]
                let kind = (properties?["kind"] as? [String: Any])?["enum"] as? [String]
                return kind == ["metric"]
            }
        )
        let properties = try XCTUnwrap(variant["properties"] as? [String: Any])
        let unit = try XCTUnwrap(properties["unit"] as? [String: Any])

        XCTAssertEqual(unit["enum"] as? [String], MetricUnit.modelStatableCases.map(\.rawValue))
    }

    /// The blocker of #186's review: a metric card is a figure **and a target
    /// for it**, so offering `beatsPerMinute` would offer the model a way to
    /// prescribe a heart rate — which ground rule 7 forbids (US-3 AC3). The
    /// schema does not list the unit, and the description does not name it.
    func testTheUnitEnumOffersNoHeartRate() throws {
        let variant = try XCTUnwrap(
            try variants().first {
                let properties = $0["properties"] as? [String: Any]
                let kind = (properties?["kind"] as? [String: Any])?["enum"] as? [String]
                return kind == ["metric"]
            }
        )
        let properties = try XCTUnwrap(variant["properties"] as? [String: Any])
        let unit = try XCTUnwrap(properties["unit"] as? [String: Any])
        let cases = try XCTUnwrap(unit["enum"] as? [String])

        XCTAssertFalse(cases.contains(MetricUnit.beatsPerMinute.rawValue))
        XCTAssertFalse(try XCTUnwrap(unit["description"] as? String).contains("beatsPerMinute"))
        XCTAssertFalse(try XCTUnwrap(unit["description"] as? String).contains("heart rate"))
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

    /// The field order is asked for by the system prompt, for every provider:
    /// `propertyOrdering` is not in Gemini's documented `responseJsonSchema`
    /// keywords, so the one schema all three receive must not carry it.
    func testTheSystemPromptListsTheReportFieldsInSchemaOrder() throws {
        let system = AnalysisPromptBuilder.systemPrompt
        let positions = try ["- headline:", "- verdict:", "- lead:", "- summary:", "- cards:"].map {
            try XCTUnwrap(system.range(of: $0)?.lowerBound, $0)
        }

        XCTAssertEqual(positions, positions.sorted())
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
