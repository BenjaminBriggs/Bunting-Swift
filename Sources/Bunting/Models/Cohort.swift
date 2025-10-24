import Foundation

/// A named group of users defined by conditions
public struct Cohort: Codable, Sendable {
    public let name: String
    public let description: String?
    public let conditions: [Condition]

    public init(
        name: String,
        description: String?,
        conditions: [Condition]
    ) {
        self.name = name
        self.description = description
        self.conditions = conditions
    }
}
