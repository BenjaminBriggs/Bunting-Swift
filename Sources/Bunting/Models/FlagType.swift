import Foundation

/// Supported flag value types
public enum FlagType: String, Codable, Sendable {
    case boolean
    case string
    case integer
    case double
    case date
    case json
}
