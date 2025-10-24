import Foundation

/// A condition used for targeting rules
public struct Condition: Codable, Sendable, Hashable {
    public let id: String
    public let type: ConditionType
    public let values: [String]
    public let `operator`: ConditionOperator

    public init(
        id: String,
        type: ConditionType,
        values: [String],
        operator: ConditionOperator
    ) {
        self.id = id
        self.type = type
        self.values = values
        self.operator = `operator`
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case values
        case `operator`
    }
}

/// Supported condition types for targeting
public enum ConditionType: String, Codable, Sendable, Hashable {
    // Number/Version conditions
    case osVersion = "os_version"
    case appVersion = "app_version"
    case buildNumber = "build_number"

    // List conditions
    case platform
    case deviceModel = "device_model"
    case region
    case locale
    case cohort

    // Custom conditions
    case customAttribute = "custom_attribute"
}

/// Operators for condition evaluation
public enum ConditionOperator: String, Codable, Sendable, Hashable {
    // Number/version comparisons
    case equals
    case doesNotEquals = "does_not_equals"
    case between
    case greaterThanOrEqual = "greater_than_or_equal"
    case greaterThan = "greater_than"
    case lessThanOrEqual = "less_than_or_equal"
    case lessThan = "less_than"

    // List comparisons
    case `in`
    case notIn = "not_in"

    // Custom
    case custom
}
