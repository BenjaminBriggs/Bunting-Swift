import Foundation

/// Represents the deployment environment for flag evaluation
public enum BuntingEnvironment: String, Codable, Sendable {
    case development
    case staging
    case production
}
