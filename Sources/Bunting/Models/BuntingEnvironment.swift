import Foundation

/// Represents the deployment environment for flag evaluation
///
/// Each flag can have different values per environment, allowing you to:
/// - Test new features in development before beta
/// - Validate changes in beta with production-like data
/// - Deploy tested features to production
///
/// Switch environments using ``Bunting/setEnvironment(_:)`` or by configuring
/// ``Bunting`` with a specific environment at startup.
public enum BuntingEnvironment: String, Codable, Sendable {
    /// Development environment for local testing and feature development
    case development

    /// Beta environment for pre-production validation
    case beta

    /// Production environment for live users
    case production
}
