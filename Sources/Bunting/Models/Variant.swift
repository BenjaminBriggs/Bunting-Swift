import Foundation

/// A variant represents a conditional override for a flag value
public struct Variant: Codable, Sendable {
    public let type: VariantType
    public let order: Int
    public let value: FlagValue
    public let conditions: [Condition]?
    public let test: String?
    public let rollout: String?

    enum CodingKeys: String, CodingKey {
        case type
        case order
        case value
        case conditions
        case test
        case rollout
    }
}

/// Types of variants for flag evaluation
public enum VariantType: String, Codable, Sendable {
    case conditional
    case test
    case rollout
}

/// A type-erased flag value that can hold any supported flag type
public enum FlagValue: Codable, Sendable {
    case boolean(Bool)
    case string(String)
    case integer(Int)
    case double(Double)
    case date(Date)
    case json(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try decoding as different types
        if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            // Try to parse as ISO8601 date
            let formatter = ISO8601DateFormatter()
            if let dateValue = formatter.date(from: stringValue) {
                self = .date(dateValue)
            } else {
                // Check if it's JSON (starts with { or [)
                let trimmed = stringValue.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    self = .json(stringValue)
                } else {
                    self = .string(stringValue)
                }
            }
        } else {
            throw DecodingError.typeMismatch(
                FlagValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode flag value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .date(let value):
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: value))
        case .json(let value):
            try container.encode(value)
        }
    }
}
