import Foundation

/// The JSON Schema every provider is asked to answer in, so the reply decodes
/// as an `AnalysisReport` (US-14, #174).
///
/// Written in the subset of JSON Schema all three providers accept, so one
/// schema serves all of them:
///
/// - `type`, `properties`, `required`, `items`, `description`
/// - `enum` of strings (not `const`: Gemini's dialect does not list it)
/// - `anyOf` for the card variants, discriminated by a one-value `kind` enum
///   — six of them since #186, the last two generic over a unit rather than
///   specific to a sport
/// - `additionalProperties: false` on every object, and every property
///   required — Claude rejects any other `additionalProperties`, and Mistral's
///   strict mode expects the same
///
/// Deliberately absent:
///
/// - `minimum` / `maximum` and `minLength` / `maxLength` — Claude does not
///   support them. Whether a weight or a rest period is plausible is
///   `AnalysisReportValidator`'s job (#175).
/// - `minItems` / `maxItems` on `cards` — Claude accepts only `minItems` 0 or 1
///   and no `maxItems`; the prompt asks for zero to four cards instead. Zero
///   is a valid answer: thin data gets a lead and a full analysis, no filler
///   cards (#170).
///
/// `lead` and `summary` are declared before `cards`: an answer cut off at the
/// token limit then usually still carries a complete summary, or at least a
/// complete lead, which `AnalysisReportParser` salvages as prose. No provider
/// is guaranteed to see that order: `JSONEncoder` does not promise key order,
/// and Gemini's `propertyOrdering` is not a documented `responseJsonSchema`
/// keyword. The order the system prompt lists the fields in is what asks for
/// it, for all three; an answer that still runs out of tokens before the
/// summary falls through to the next provider.
///
/// Per provider (see the request types for the wire shape):
///
/// - Claude: `output_config.format` = `{type: "json_schema", schema}`
/// - Gemini: `generationConfig.responseJsonSchema` with `responseMimeType`
///   `application/json` — the JSON Schema field, not the OpenAPI-subset
///   `responseSchema`. The same schema as the others, no `propertyOrdering`.
/// - Mistral: `response_format` = `{type: "json_schema", json_schema: {name,
///   schema, strict: true}}`
enum AnalysisReportSchema {
    /// Identifier Mistral requires for the schema.
    static let name = "analysis_report"

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "headline": [
                "type": "string",
                "description": "One short sentence stating the verdict."
            ],
            "verdict": [
                "type": "string",
                "enum": .array(AnalysisVerdict.allCases.map { .string($0.rawValue) }),
                "description": "progress: the data supports adding load or reps. recover: rest comes first. hold: neither is justified yet."
            ],
            "lead": [
                "type": "string",
                "description": "The key takeaway in one to three sentences, at most about 50 words, readable on its own."
            ],
            "summary": [
                "type": "string",
                "description": "The full analysis as plain prose under 200 words, readable without the cards."
            ],
            "cards": [
                "type": "array",
                "description": "Zero to four recommendation cards, most important first. Empty when the data supports none.",
                "items": ["anyOf": .array(AnalysisCard.Kind.allCases.map(card))]
            ]
        ],
        "required": ["headline", "verdict", "lead", "summary", "cards"],
        "additionalProperties": false
    ]

    // MARK: - Cards

    /// The object schema of one card kind: `kind` pinned to that kind, then its
    /// own fields, all of them required.
    private static func card(_ kind: AnalysisCard.Kind) -> JSONValue {
        let kindMember = JSONValue.Member(key: "kind", value: ["type": "string", "enum": .array([.string(kind.rawValue)])])
        let members = [kindMember] + fields(of: kind)
        return .object([
            .init(key: "type", value: "object"),
            .init(key: "properties", value: .object(members)),
            .init(key: "required", value: .array(members.map { .string($0.key) })),
            .init(key: "additionalProperties", value: false)
        ])
    }

    private static func fields(of kind: AnalysisCard.Kind) -> [JSONValue.Member] {
        switch kind {
        case .progression:
            return [
                field(.exercise, "string", "The exercise name exactly as listed in the Exercises section."),
                field(.muscleGroup, "string", "The muscle group listed for that exercise."),
                field(.fromKg, "number", "The weight listed for its most recent session, in kg."),
                field(.toKg, "number", "The recommended new weight, in kg."),
                field(.reasoning, "string", "One sentence explaining the increase.")
            ]
        case .recovery:
            return [
                field(.reasoning, "string", "One or two sentences explaining why rest comes first."),
                field(.suggestedRestHours, "number", "The recommended rest before the next session, in hours.")
            ]
        case .imbalance:
            return [
                field(.groupA, "string", "The more frequently trained muscle group."),
                field(.perWeekA, "number", "Its sessions per week in the recent window."),
                field(.groupB, "string", "The less frequently trained muscle group."),
                field(.perWeekB, "number", "Its sessions per week in the recent window."),
                field(.reasoning, "string", "One sentence on how to even out the two.")
            ]
        case .metric:
            return [
                field(.label, "string", "What the figure is, e.g. Weekly distance, Long run, Weekly volume."),
                field(.from, "number", "The figure as the data stands, in the unit below."),
                field(.to, "number", "The figure you recommend, in the same unit."),
                unitField,
                field(.source, "string", "A short label for the header, e.g. Run, Ride, Strength. Empty string when none fits."),
                field(.reasoning, "string", "One sentence explaining the change.")
            ]
        case .interference:
            return [
                field(.strengthDays, "integer", "Days of the last 7 carrying a strength session, as the Week structure section states."),
                field(.cardioDays, "integer", "Days of the last 7 carrying an endurance session."),
                field(.overlapDays, "integer", "Days of the last 7 carrying both."),
                field(.reasoning, "string", "One sentence on how to separate the two.")
            ]
        case .note:
            return [
                field(.title, "string", "A short title."),
                field(.text, "string", "One or two sentences.")
            ]
        }
    }

    /// The unit of a metric card, as an `enum` of the raw values `MetricUnit`
    /// decodes — the one place the schema constrains a value rather than a
    /// type. Generated from `allCases`, so a unit added to the enum cannot be
    /// left out of the schema.
    private static let unitField = JSONValue.Member(
        key: AnalysisCard.CodingKeys.unit.rawValue,
        value: [
            "type": "string",
            "enum": .array(MetricUnit.allCases.map { .string($0.rawValue) }),
            "description": "The unit of both figures. kilograms for a weight or a weekly volume, kilometers for a distance, minutesPerKilometer for a pace (5.5 means 5:30 per km), beatsPerMinute for a heart rate, hours for a duration (4.5 means 4 h 30 min)."
        ]
    )

    private static func field(_ key: AnalysisCard.CodingKeys, _ type: String, _ description: String) -> JSONValue.Member {
        .init(key: key.rawValue, value: ["type": .string(type), "description": .string(description)])
    }
}
