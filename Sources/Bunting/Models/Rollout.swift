import Foundation

/// A percentage-based gradual rollout configuration
public struct Rollout: Codable, Sendable {
    public let name: String
    public let description: String?
    public let type: String
    public let salt: String
    public let conditions: [Condition]
    public let percentage: Int

    public init(
        name: String,
        description: String?,
        type: String,
        salt: String,
        conditions: [Condition],
        percentage: Int
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.salt = salt
        self.conditions = conditions
        self.percentage = percentage
    }
}
