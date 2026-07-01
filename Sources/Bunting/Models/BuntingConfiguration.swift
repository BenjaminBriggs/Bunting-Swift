import Foundation

/// The root configuration object containing all flags, tests, and rollouts
///
/// This is the complete feature flag configuration fetched from the CDN and verified
/// with JWS signatures. It contains:
/// - **flags**: All feature flags with environment-specific variants
/// - **tests**: A/B test definitions for bucketing users into groups
/// - **rollouts**: Gradual rollout definitions for percentage-based deployment
///
/// The configuration is:
/// - Loaded asynchronously from the CDN on app startup
/// - Verified with cryptographic signatures using embedded public keys
/// - Cached locally with ETag-based validation
/// - Periodically refreshed when the app enters the foreground
///
/// Access the active configuration via ``Bunting/configuration``.
/// Subscribe to changes via ``Bunting/eventsDelegate``.
public struct BuntingConfiguration: Decodable, Sendable {
    /// Schema version for backwards compatibility
    public let schemaVersion: Int

    /// Unique configuration version (format: YYYY-MM-DD.N)
    ///
    /// Used to track which configuration version is active and to invalidate
    /// the evaluation cache when a new version is published.
    public let configVersion: String

    /// When this configuration was published to the CDN
    public let publishedAt: Date

    /// The app identifier this configuration is for
    ///
    /// Allows multiple independent apps to use the same Bunting instance.
    public let appIdentifier: String

    /// All feature flags in this configuration
    ///
    /// Maps flag keys to flag definitions with environment-specific variants.
    public let flags: [String: Flag]

    /// A/B test definitions for user bucketing
    ///
    /// Maps test names to test definitions. Used by test variants
    /// to deterministically bucket users into groups.
    public let tests: [String: Test]

    /// Gradual rollout definitions for percentage-based deployment
    ///
    /// Maps rollout names to rollout definitions. Used by rollout variants
    /// to gradually roll out features to a percentage of users.
    public let rollouts: [String: Rollout]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case configVersion = "config_version"
        case publishedAt = "published_at"
        case appIdentifier = "app_identifier"
        case flags
        case tests
        case rollouts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        configVersion = try container.decode(String.self, forKey: .configVersion)
        appIdentifier = try container.decode(String.self, forKey: .appIdentifier)

        // Decode publishedAt as ISO8601
        let publishedAtString = try container.decode(String.self, forKey: .publishedAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: publishedAtString) {
            publishedAt = date
        } else {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: publishedAtString) {
                publishedAt = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .publishedAt,
                    in: container,
                    debugDescription: "Invalid ISO8601 date format"
                )
            }
        }

        flags = try container.decode([String: Flag].self, forKey: .flags)
        tests = try container.decode([String: Test].self, forKey: .tests)
        rollouts = try container.decode([String: Rollout].self, forKey: .rollouts)
    }
}
