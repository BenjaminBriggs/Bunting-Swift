import Foundation

/// A single targeting rule that the evaluation engine tests against the current context
///
/// Conditions are the building blocks of flag variants and ``Test``/``Rollout``
/// precondition lists. Each condition specifies:
/// - **What to check** (``ConditionType``): platform, OS version, app version, region, etc.
/// - **How to compare** (``ConditionOperator``): equality, range, list membership, etc.
/// - **What to compare against** (``values``): one or more reference strings
///
/// All conditions in a list must evaluate to `true` for the parent rule to match
/// (logical AND). There is no built-in OR; model OR logic as separate variants.
///
/// ## Example
///
/// Match users on iOS 18 or later:
/// ```json
/// {
///   "type": "os_version",
///   "operator": "greater_than_or_equal",
///   "values": ["18.0"]
/// }
/// ```
///
/// Match users in the United States or Canada:
/// ```json
/// {
///   "type": "region",
///   "operator": "in",
///   "values": ["US", "CA"]
/// }
/// ```
public struct Condition: Codable, Sendable, Hashable {
    /// The attribute to evaluate
    public let type: ConditionType

    /// One or more reference values used during comparison
    ///
    /// Interpretation depends on `type` and `operator`:
    /// - Version conditions: a single version string, or two strings for `between`
    /// - List conditions (`in`, `not_in`): one or more values (e.g., `["iOS"]`)
    /// - `custom_attribute`: a single string naming the attribute (`values[0]`)
    /// - `language`: one or more bare language codes (e.g., `["en", "es"]`)
    public let values: [String]

    /// The comparison operator to apply
    public let `operator`: ConditionOperator

    public init(
        type: ConditionType,
        values: [String],
        operator: ConditionOperator
    ) {
        self.type = type
        self.values = values
        self.operator = `operator`
    }

    enum CodingKeys: String, CodingKey {
        case type
        case values
        case `operator`
    }
}

/// The attribute a ``Condition`` targets when evaluating the current context
public enum ConditionType: String, Codable, Sendable, Hashable {
    // MARK: Version conditions (use numeric operators)

    /// The host operating system's version string (e.g., `"18.0"`)
    case osVersion = "os_version"

    /// The app's marketing version (e.g., `"2.5.0"`)
    case appVersion = "app_version"

    /// The app's build number as a string (e.g., `"1234"`)
    case buildNumber = "build_number"

    // MARK: List conditions (use `in` / `not_in`)

    /// The OS platform: `"iOS"`, `"iPadOS"`, `"macOS"`, `"watchOS"`, `"tvOS"`, `"visionOS"`
    case platform

    /// The device model identifier (e.g., `"iPhone16,2"`)
    case deviceModel = "device_model"

    /// The device's region/country code (e.g., `"US"`, `"GB"`)
    case region

    /// The device's language code (e.g., `"en"`, `"es"`), derived from the device locale
    case language

    // MARK: Custom conditions

    /// A custom, app-defined attribute; `values[0]` names the attribute,
    /// resolved at runtime via the `customAttributes` closure passed to ``Bunting/configure(environment:context:keychainAccessGroup:customAttributes:)``
    case customAttribute = "custom_attribute"
}

/// The comparison operator applied by a ``Condition`` during evaluation
public enum ConditionOperator: String, Codable, Sendable, Hashable {
    // MARK: Version / numeric comparisons

    /// Exact match
    case equals

    /// Inverse exact match
    case doesNotEquals = "does_not_equals"

    /// Inclusive range check; requires exactly two values in ``Condition/values``
    case between

    /// Context value ≥ reference value
    case greaterThanOrEqual = "greater_than_or_equal"

    /// Context value > reference value
    case greaterThan = "greater_than"

    /// Context value ≤ reference value
    case lessThanOrEqual = "less_than_or_equal"

    /// Context value < reference value
    case lessThan = "less_than"

    // MARK: List comparisons

    /// Context value is contained in ``Condition/values``
    case `in`

    /// Context value is not contained in ``Condition/values``
    case notIn = "not_in"

    // MARK: Custom attribute

    /// Used exclusively with ``ConditionType/customAttribute``; delegates evaluation
    /// to the app-supplied `customAttributes` resolver
    case custom
}
