import Foundation

/// A feature flag with environment-specific configurations
public struct Flag: Codable, Sendable {
    public let type: FlagType
    public let description: String?
    public let development: EnvironmentConfig
    public let staging: EnvironmentConfig
    public let production: EnvironmentConfig

    /// Get the configuration for a specific environment
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
public struct EnvironmentConfig: Codable, Sendable {
    public let `default`: FlagValue
    public let variants: [Variant]

    enum CodingKeys: String, CodingKey {
        case `default`
        case variants
    }
}
