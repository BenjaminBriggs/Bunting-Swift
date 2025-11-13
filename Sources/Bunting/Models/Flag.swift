import Foundation
import OSLog

/// A feature flag with environment-specific configurations
///
/// Flags contain everything needed to evaluate their value, including:
/// - The flag's data type (boolean, string, integer, etc.)
/// - Environment-specific variants (conditional, test, rollout)
/// - Default values for each environment
///
/// Flags are keyed by their flag key (e.g., "feature/new_design") and accessed
/// via type-safe methods on ``Bunting`` like ``Bunting/bool(_:default:)`` or
/// ``Bunting/string(_:default:)``.
///
/// Access flags using the appropriate method for their type:
/// ```swift
/// let showFeature = Bunting.shared.bool("feature/new_design", default: false)
/// let tier = Bunting.shared.string("pricing/tier", default: "free")
/// ```
public struct Flag: Decodable, Sendable {
    /// The flag's value type (boolean, string, integer, double, date, or json)
    public let type: FlagType

    /// Human-readable description of what this flag controls
    public let description: String?

    /// Configuration for the development environment
    public let development: EnvironmentConfig

    /// Configuration for the staging environment
    public let staging: EnvironmentConfig

    /// Configuration for the production environment
    public let production: EnvironmentConfig

    public init(
        type: FlagType,
        description: String?,
        development: EnvironmentConfig,
        staging: EnvironmentConfig,
        production: EnvironmentConfig
    ) {
        self.type = type
        self.description = description
        self.development = development
        self.staging = staging
        self.production = production
    }

    /// Get the configuration for a specific environment
    ///
    /// - Parameter environment: The environment to get configuration for
    /// - Returns: The variant list and default value for that environment
    public func config(for environment: BuntingEnvironment) -> EnvironmentConfig {
        switch environment {
        case .development:
            return development
        case .staging:
            return staging
        case .production:
            return production
        }
    }
}

/// Environment-specific flag configuration
///
/// Contains the variants to evaluate and the default value for a flag in a specific environment.
/// Variants are evaluated in order (first match wins):
/// 1. **Conditional variants**: Evaluated against context and custom attributes
/// 2. **Test variants**: Deterministically bucket users; return group value if matched
/// 3. **Rollout variants**: Bucket users and check rollout percentage
/// 4. **Fallback**: Return the `default` value if no variant matches
///
/// The `default` value is returned when:
/// - No variants are defined
/// - No variant conditions match
/// - Configuration is not loaded yet
/// - The flag key doesn't exist
public struct EnvironmentConfig: Decodable, Sendable {
    /// The default value to return if no variants match
    ///
    /// Used as a fallback when:
    /// - The flag is not configured
    /// - Configuration has not been loaded
    /// - All variant conditions fail to match
    public let `default`: FlagValue

    /// List of variants to evaluate in order
    ///
    /// Variants are evaluated in ascending order by their `order` property.
    /// The first variant whose conditions match is returned.
    /// If empty, the default value is always returned.
    public let variants: [Variant]

    public init(default: FlagValue, variants: [Variant]) {
        self.default = `default`
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey {
        case `default`
        case defaultValue = "defaultValue"
        case defaultdefault = "defaultdefault"
        case variants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode variants (default to empty array if missing)
        let variants = (try? container.decode([Variant].self, forKey: .variants)) ?? []

        // Try standard key first
        if let value = try? container.decode(FlagValue.self, forKey: .default) {
            self.init(default: value, variants: variants)
            return
        }

        // Fallback: accept "defaultValue" (legacy seed shape)
        if let value = try? container.decode(FlagValue.self, forKey: .defaultValue) {
            BuntingLog.config.notice(
                "Using legacy 'defaultValue' key for environment config (path: \(decoder.codingPath.map { $0.stringValue }.joined(separator: ".")), privacy: .public)"
            )
            self.init(default: value, variants: variants)
            return
        }

        // Fallback: accept misspelled "defaultdefault" if present
        if let value = try? container.decode(FlagValue.self, forKey: .defaultdefault) {
            BuntingLog.config.error(
                "Non-standard key 'defaultdefault' found; accepting as default (path: \(decoder.codingPath.map { $0.stringValue }.joined(separator: ".")), privacy: .public)"
            )
            self.init(default: value, variants: variants)
            return
        }

        // If all keys missing, throw a descriptive error
        let ctx = DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Missing required 'default' value in environment config"
        )
        throw DecodingError.valueNotFound(FlagValue.self, ctx)
    }
}
