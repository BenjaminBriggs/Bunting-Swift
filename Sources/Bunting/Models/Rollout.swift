import Foundation

/// A percentage-based gradual rollout definition
///
/// A `Rollout` exposes a single flag value to a steadily increasing share of users,
/// letting you deploy a feature safely by starting at a small percentage and
/// expanding over time without a full re-deployment.
///
/// Variants that reference a rollout use ``VariantType/rollout`` and set
/// ``Variant/rollout`` to this rollout's `name`. The evaluator:
/// 1. Checks ``conditions`` — if any condition fails, the variant is skipped.
/// 2. Computes the user's bucket (1–100) using SHA-256 over `"\(salt):\(localID)"`.
/// 3. Returns the variant's value if the bucket ≤ ``percentage``; otherwise skips.
///
/// Assignment is **deterministic**: a user's bucket for a given `salt` never changes,
/// so increasing `percentage` only adds new users — it never moves existing ones.
///
/// ## Example
///
/// ```json
/// {
///   "name": "new_checkout_rollout",
///   "salt": "unique-salt-xyz789",
///   "conditions": [],
///   "percentage": 20
/// }
/// ```
///
/// This enrolls ~20% of users. Raise `percentage` in the admin UI to expand the rollout.
///
/// - SeeAlso: ``Test`` for multi-group A/B tests.
public struct Rollout: Codable, Sendable {
    /// The unique name for this rollout, referenced by ``Variant/rollout``
    public let name: String

    /// An optional human-readable description of the feature being rolled out
    public let description: String?

    /// The rollout type identifier (currently always `"rollout"`)
    public let type: String

    /// The salt used when computing user bucket assignments
    ///
    /// Combined with the device's local ID as `"\(salt):\(localID)"` before hashing.
    /// Keeping the salt stable ensures the same users remain enrolled as the
    /// percentage increases. Changing the salt re-randomises enrollment.
    public let salt: String

    /// Preconditions that must all pass before the rollout percentage is checked
    ///
    /// If any condition fails, the variant is skipped entirely. Use conditions to
    /// limit rollouts to a specific platform, OS version range, or region.
    public let conditions: [Condition]

    /// The percentage of users to enroll (1–100)
    ///
    /// Users whose bucket (1–100) is ≤ this value receive the rollout value.
    /// Set to 100 to complete the rollout for all users; set to 0 to disable.
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
