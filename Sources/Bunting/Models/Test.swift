import Foundation

/// An A/B test configuration with deterministic bucketing
public struct Test: Codable, Sendable {
    public let name: String
    public let description: String?
    public let type: String
    public let salt: String
    public let conditions: [Condition]
}
