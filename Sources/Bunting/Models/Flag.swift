import Foundation

/// A feature flag with environment-specific configurations
public struct Flag: Codable, Sendable {
    public let type: FlagType
    public let description: String?
    public let development: EnvironmentConfig
    public let staging: EnvironmentConfig
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

    public init(default: FlagValue, variants: [Variant]) {
        self.default = `default`
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey {
        case `default`
        case variants
    }
}
