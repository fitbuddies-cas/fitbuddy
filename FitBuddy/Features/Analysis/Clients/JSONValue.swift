import Foundation

/// A JSON document written as a Swift literal, so a request body can carry a
/// JSON Schema without a resource file or an untyped dictionary (#174).
///
/// Only the cases a schema needs: strings, booleans, arrays and objects. A
/// schema without numeric bounds has no numbers in it.
///
/// Objects keep their members in declaration order. `JSONEncoder` does not
/// promise that order on the wire, so no provider is guaranteed to see it; the
/// order of the answer's fields is asked for by the system prompt.
indirect enum JSONValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([Member])

    /// One key of an object, in the position it was declared.
    struct Member: Equatable, Sendable {
        let key: String
        let value: JSONValue
    }

    /// The value stored under `key`, when this is an object that has one.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            try value.encode(to: encoder)
        case .bool(let value):
            try value.encode(to: encoder)
        case .array(let values):
            try values.encode(to: encoder)
        case .object(let members):
            var container = encoder.container(keyedBy: MemberKey.self)
            for member in members {
                try container.encode(member.value, forKey: MemberKey(stringValue: member.key))
            }
        }
    }

    /// An object key taken from the member itself rather than from a fixed
    /// `CodingKeys` enum.
    private struct MemberKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// Keeps the literal's order — the reason this is not a `[String: JSONValue]`.
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(elements.map { Member(key: $0.0, value: $0.1) })
    }
}
