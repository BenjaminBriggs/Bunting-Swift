import Foundation

/// A variant represents a conditional override for a flag value
///
/// Variants are the core mechanism for flag evaluation. Each variant specifies:
/// - **Type**: How to evaluate this variant (conditional, test, or rollout)
/// - **Order**: Priority order for evaluation (lower values evaluated first)
/// - **Value**: The flag value to return if this variant matches
/// - **Conditions**: What must be true for this variant to match
///
/// Variants are evaluated in ascending order by their `order` property. The first
/// variant whose conditions match is returned; no further variants are considered.
///
/// ## Variant Types
///
/// - **Conditional**: Returns value if all conditions match context/attributes
/// - **Test**: Deterministically buckets users into groups for A/B testing
/// - **Rollout**: Gradually rolls out to a percentage of users
///
/// If no variant matches, the environment's default value is returned.
public struct Variant: Codable, Sendable {
    /// The variant type (conditional, test, or rollout)
    public let type: VariantType

    /// Evaluation order (ascending; lower values evaluated first)
    ///
    /// Variants are sorted by order before evaluation. The first variant
    /// whose conditions match is returned, so order determines precedence.
    public let order: Int

    /// The flag value for this variant
    ///
    /// Used by:
    /// - Conditional variants: Always returned if conditions match
    /// - Test variants: Returned for simple tests without groups
    /// - Rollout variants: Returned if user qualifies for rollout
    ///
    /// Ignored for test variants that use `values` for group-based assignment.
    public let value: FlagValue?

    /// Group-specific values for test variants
    ///
    /// Maps group names to flag values. Used by test variants to return
    /// different values based on which test group the user is bucketed into.
    ///
    /// Only used for test variants; `nil` for conditional and rollout variants.
    public let values: [String: FlagValue]?

    /// Conditions that must match for this variant to be selected
    ///
    /// All conditions must be true for the variant to match.
    /// If empty or `nil`, variant always matches (subject to test/rollout qualification).
    ///
    /// Conditions can check:
    /// - Platform (iOS, macOS, watchOS, tvOS)
    /// - OS version
    /// - App version
    /// - Device model
    /// - Language/region
    /// - Custom attributes
    public let conditions: [Condition]?

    /// Test name for test variants
    ///
    /// References a test defined in the configuration.
    /// Only used for test variants; `nil` for conditional and rollout variants.
    public let test: String?

    /// Rollout name for rollout variants
    ///
    /// References a rollout defined in the configuration.
    /// Only used for rollout variants; `nil` for conditional and test variants.
    public let rollout: String?

    public init(
        type: VariantType,
        order: Int,
        value: FlagValue?,
        values: [String: FlagValue]?,
        conditions: [Condition]?,
        test: String?,
        rollout: String?
    ) {
        self.type = type
        self.order = order
        self.value = value
        self.values = values
        self.conditions = conditions
        self.test = test
        self.rollout = rollout
    }

    enum CodingKeys: String, CodingKey {
        case type
        case order
        case value
        case values
        case conditions
        case test
        case rollout
    }
}

/// Types of variants for flag evaluation
///
/// The variant type determines how the variant's value is selected:
/// - **Conditional**: Simple if/then logic based on conditions
/// - **Test**: A/B testing with deterministic user bucketing
/// - **Rollout**: Percentage-based gradual deployment
public enum VariantType: String, Codable, Sendable {
    /// Conditional variant: return value if conditions match
    ///
    /// Used for simple logic like "show this value in the US and Canada"
    /// or "show this value on iOS 18+".
    case conditional

    /// Test variant: A/B test with deterministic user bucketing
    ///
    /// Users are bucketed into groups based on the test's salt and their device ID.
    /// Bucketing is deterministic: the same user always gets the same group.
    case test

    /// Rollout variant: Percentage-based gradual deployment
    ///
    /// Users are bucketed by percentage (0-100) based on salt and device ID.
    /// Gradual rollouts allow safe deployment: start at 1%, increase to 100%.
    case rollout
}

/// A type-erased flag value that can hold any supported flag type
///
/// `FlagValue` is an enum that can store values of any type supported by Bunting:
/// - **boolean**: Simple true/false values
/// - **string**: Text configuration values
/// - **integer**: Whole number values
/// - **double**: Floating-point values
/// - **date**: ISO8601 formatted dates
/// - **json**: Structured data as UTF-8 encoded JSON strings
///
/// Flag values are decoded from JSON configuration automatically. The SDK handles:
/// - Type detection during decoding (integer vs double vs date)
/// - ISO8601 date parsing
/// - JSON object/array detection
///
/// When accessing flags via ``Bunting``, use the type-specific methods like
/// ``Bunting/bool(_:default:)`` or ``Bunting/string(_:default:)`` rather than
/// working with `FlagValue` directly. If the actual type doesn't match the
/// requested type, the default value is returned.
public enum FlagValue: Codable, Sendable {
    /// Boolean true/false value
    case boolean(Bool)

    /// String text value
    case string(String)

    /// Integer whole number value
    case integer(Int)

    /// Double floating-point value
    case double(Double)

    /// Date ISO8601 formatted date/time value
    case date(Date)

    /// JSON object or array value (UTF-8 encoded string)
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
