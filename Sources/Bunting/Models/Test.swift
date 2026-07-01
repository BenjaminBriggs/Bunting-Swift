import Foundation

/// An A/B test definition that deterministically buckets users into named groups
///
/// A `Test` splits eligible users across multiple named groups (e.g., `control` and
/// `treatment`) and assigns each user to exactly one group. Assignment is
/// **deterministic**: the same device always lands in the same group for a given test,
/// regardless of when or how often the flag is evaluated.
///
/// Variants that reference a test use ``VariantType/test`` and set ``Variant/test``
/// to this test's `name`. The evaluator:
/// 1. Checks ``conditions`` — if any condition fails, the variant is skipped entirely.
/// 2. Computes the user's bucket (1–100) using SHA-256 over `"\(salt):\(localID)"`.
/// 3. Walks ``groups`` in order, accumulating percentages, and returns the first
///    group whose cumulative percentage is ≥ the user's bucket.
/// 4. Looks up the group's name in ``Variant/values`` to get the flag value.
///
/// ## Example
///
/// ```json
/// {
///   "name": "checkout_cta_test",
///   "salt": "unique-salt-abc123",
///   "conditions": [],
///   "groups": [
///     { "name": "control",   "percentage": 50 },
///     { "name": "treatment", "percentage": 50 }
///   ]
/// }
/// ```
///
/// - SeeAlso: ``Rollout`` for binary (enrolled/not-enrolled) percentage rollouts.
/// - SeeAlso: ``TestGroup`` for group definitions.
public struct Test: Codable, Sendable {
    /// The unique name for this test, referenced by ``Variant/test``
    public let name: String

    /// An optional human-readable description of what the test measures
    public let description: String?

    /// The test type identifier (currently always `"test"`)
    public let type: String

    /// The salt used when computing user bucket assignments
    ///
    /// Combined with the device's local ID as `"\(salt):\(localID)"` before hashing.
    /// Changing the salt produces a different bucket assignment for every user,
    /// effectively re-randomising the test population.
    public let salt: String

    /// Preconditions that must all pass before bucketing the user
    ///
    /// If any condition fails, the entire variant is skipped and evaluation moves
    /// to the next variant. Useful for restricting a test to a specific platform,
    /// app version, or region before incurring bucketing overhead.
    public let conditions: [Condition]

    /// Named groups with their traffic percentage allocations
    ///
    /// Percentages should sum to 100. Users whose bucket exceeds the sum of all
    /// group percentages are not enrolled in the test (the variant is skipped).
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

    /// Returns the group name for the given bucket, or `nil` if the bucket falls
    /// outside all groups' cumulative percentage ranges
    ///
    /// - Parameter bucket: A value from 1 to 100 produced by the bucketing algorithm
    /// - Returns: The name of the first group whose cumulative percentage is ≥ `bucket`,
    ///   or `nil` if the bucket is beyond all groups' coverage
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

/// A named group within an A/B test with a traffic percentage allocation
///
/// Groups are evaluated in order. The first group whose cumulative percentage
/// covers the user's bucket wins. Percentages should sum to 100 across all
/// groups in a test; any remainder means that fraction of users is not enrolled.
public struct TestGroup: Codable, Sendable {
    /// The group name, matched against keys in ``Variant/values`` to retrieve the flag value
    public let name: String

    /// Traffic allocation for this group, expressed as a whole percentage (0–100)
    ///
    /// Combined with preceding groups' percentages to determine the bucket range
    /// that maps to this group. For example, two groups at 50% each cover
    /// buckets 1–50 and 51–100 respectively.
    public let percentage: Int

    public init(name: String, percentage: Int) {
        self.name = name
        self.percentage = percentage
    }
}
