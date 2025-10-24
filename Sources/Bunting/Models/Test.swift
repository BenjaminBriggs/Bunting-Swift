import Foundation

/// An A/B test configuration with deterministic bucketing
public struct Test: Codable, Sendable {
    public let name: String
    public let description: String?
    public let type: String
    public let salt: String
    public let conditions: [Condition]
    public let groups: [TestGroup]?

    public init(
        name: String,
        description: String?,
        type: String,
        salt: String,
        conditions: [Condition],
        groups: [TestGroup]?
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.salt = salt
        self.conditions = conditions
        self.groups = groups
    }

    /// Determines which group a bucket falls into based on percentage splits
    /// Returns the group name if the bucket falls within a group's range
    func assignGroup(bucket: Int) -> String? {
        guard let groups = groups, groups.isEmpty == false else {
            return nil
        }

        var cumulativePercentage = 0
        for group in groups {
            cumulativePercentage += group.percentage
            if bucket <= cumulativePercentage {
                return group.name
            }
        }

        return nil
    }
}

/// A test group with name and percentage allocation
public struct TestGroup: Codable, Sendable {
    public let name: String
    public let percentage: Int

    public init(name: String, percentage: Int) {
        self.name = name
        self.percentage = percentage
    }
}
