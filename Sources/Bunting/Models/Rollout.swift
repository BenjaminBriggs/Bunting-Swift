import Foundation

/// A percentage-based gradual rollout configuration
public struct Rollout: Codable, Sendable {
    public let name: String
    public let description: String?
    public let type: String
    public let salt: String
    public let conditions: [Condition]
    public let percentage: Int
}
