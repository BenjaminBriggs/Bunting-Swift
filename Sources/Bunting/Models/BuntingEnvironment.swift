import Foundation

/// Represents the deployment environment for flag evaluation
///
/// Each flag can have different values per environment, allowing you to:
/// - Test new features in development before staging
/// - Validate changes in staging with production-like data
/// - Deploy tested features to production
///
/// Switch environments using ``Bunting/setEnvironment(_:)`` or by configuring
/// ``Bunting`` with a specific environment at startup.
public enum BuntingEnvironment: String, Codable, Sendable {
    /// Development environment for local testing and feature development
    case development

    /// Staging environment for pre-production validation
    case staging

    /// Production environment for live users
    case production
}
