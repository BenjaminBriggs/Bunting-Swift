import Foundation
import OSLog

/// A feature flag with environment-specific configurations
public struct Flag: Decodable, Sendable {
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
public struct EnvironmentConfig: Decodable, Sendable {
    public let `default`: FlagValue
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
            BuntingLog.config.notice("Using legacy 'defaultValue' key for environment config (path: \(decoder.codingPath.map { $0.stringValue }.joined(separator: ".")), privacy: .public)")
            self.init(default: value, variants: variants)
            return
        }

        // Fallback: accept misspelled "defaultdefault" if present
        if let value = try? container.decode(FlagValue.self, forKey: .defaultdefault) {
            BuntingLog.config.error("Non-standard key 'defaultdefault' found; accepting as default (path: \(decoder.codingPath.map { $0.stringValue }.joined(separator: ".")), privacy: .public)")
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
