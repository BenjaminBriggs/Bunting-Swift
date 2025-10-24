import Foundation

/// A named group of users defined by conditions
public struct Cohort: Codable, Sendable {
    public let name: String
    public let description: String?
    public let conditions: [Condition]
}
