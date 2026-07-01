import Foundation

/// Supported flag value types
///
/// Bunting supports six types of flag values, each optimized for different use cases:
/// - **boolean**: Feature toggles and simple on/off flags
/// - **string**: Configuration values like feature names or labels
/// - **integer**: Numeric configs like rate limits or thresholds
/// - **double**: Floating-point values for percentages, scales, or calculations
/// - **date**: Time-based configurations like feature launch/sunset dates
/// - **json**: Complex structured data like layout configurations or color schemes
///
/// When accessing flags, you must know the expected type. Type mismatches return the default value.
public enum FlagType: String, Codable, Sendable {
    /// Boolean true/false values for simple feature toggles
    case boolean = "bool"

    /// String text values for configuration or labels
    case string

    /// Integer whole number values for counts and thresholds
    case integer = "int"

    /// Double floating-point values for percentages and calculations
    case double

    /// Date ISO8601 formatted date/time values for time-based features
    case date

    /// JSON object or array values (UTF-8 encoded strings) for complex data
    case json
}
