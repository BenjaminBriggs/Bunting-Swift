import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

/// Runtime context for flag evaluation
///
/// `EvaluationContext` contains all stable device and app information that affects
/// flag evaluation. It includes platform, OS version, app version, device model,
/// and language information.
///
/// The context is used to:
/// - Evaluate conditional variants based on platform/version/device constraints
/// - Compute a stable hash for evaluation caching
/// - Provide stable inputs for condition evaluation
///
/// The context is set once during initialization and does not change during runtime.
/// Custom, dynamic attributes should be provided via a custom attributes resolver.
///
/// Create a context with current system info using ``current(appVersion:buildNumber:)``
/// or provide explicit values for testing.
public struct EvaluationContext: Sendable, Hashable {
    /// The platform identifier ("iOS", "iPadOS", "macOS", "watchOS", "tvOS", or "unknown")
    ///
    /// Used to evaluate platform-specific flag variants (e.g., iOS-only features).
    public let platform: String

    /// The operating system version string (e.g., "18.1")
    ///
    /// Used to evaluate version-gated features (e.g., "iOS 18+ only").
    public let osVersion: String

    /// The app version from Info.plist (e.g., "1.2.3")
    ///
    /// Used to evaluate version-specific flags and deprecations.
    public let appVersion: String

    /// The build number from Info.plist (e.g., "42")
    ///
    /// Used for granular version-based feature targeting.
    public let buildNumber: String

    /// The device model (e.g., "iPhone", "iPad", "Mac")
    ///
    /// Used to evaluate device-type specific flags (phone vs tablet vs desktop).
    public let deviceModel: String

    /// The user's region identifier (e.g., "US", "GB", "FR"), or `nil` if not set
    ///
    /// Used for region-specific features, pricing, or compliance rules.
    public let region: String?

    /// The user's language code (e.g., "en", "es", "fr")
    ///
    /// Derived from the device locale's language component. Used for
    /// language-specific feature targeting.
    public let language: String

    /// Creates an evaluation context with explicit values
    ///
    /// - Parameters:
    ///   - platform: Platform identifier (iOS, macOS, etc.)
    ///   - osVersion: OS version string
    ///   - appVersion: App version string
    ///   - buildNumber: Build number string
    ///   - deviceModel: Device model string
    ///   - region: User's region identifier (country code)
    ///   - language: User's language code
    public init(
        platform: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        region: String?,
        language: String
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.region = region
        self.language = language
    }

    /// Resolver for custom flag attributes
    ///
    /// A closure that evaluates whether a named attribute is active for the current user.
    /// Return `true` if the attribute is enabled, `false` otherwise.
    ///
    /// Used by conditional variants to implement custom logic beyond the built-in
    /// platform/version/device/language checks. For example:
    /// ```swift
    /// { attribute in
    ///     switch attribute {
    ///     case "pro_user": return subscription.isPro
    ///     case "beta_tester": return user.beta == true
    ///     default: return false
    ///     }
    /// }
    /// ```
    public typealias CustomAttributeResolver = @Sendable (String) -> Bool

    /// Computes a hash of the context for evaluation caching
    ///
    /// The hash includes all stable device and app attributes. This hash is used
    /// as part of the cache key for memoized flag evaluations. The same context
    /// always produces the same hash, enabling effective caching.
    ///
    /// - Returns: Stable hash value for this context
    public func computeHash() -> Int {
        var hasher = Hasher()
        hasher.combine(platform)
        hasher.combine(osVersion)
        hasher.combine(appVersion)
        hasher.combine(buildNumber)
        hasher.combine(deviceModel)
        hasher.combine(region)
        hasher.combine(language)
        return hasher.finalize()
    }

    /// Creates an evaluation context with current system information
    ///
    /// Automatically detects the current platform, OS version, device model, region, and language.
    /// App version and build number are read from `Info.plist` unless explicitly provided.
    ///
    /// This is the recommended way to create a context for normal app usage.
    ///
    /// - Parameters:
    ///   - appVersion: App version override (defaults to CFBundleShortVersionString from Info.plist)
    ///   - buildNumber: Build number override (defaults to CFBundleVersion from Info.plist)
    /// - Returns: An evaluation context populated with current system information
    ///
    /// ## Example
    /// ```swift
    /// // Use current system info
    /// let context = EvaluationContext.current()
    ///
    /// // Override version for testing
    /// let context = EvaluationContext.current(appVersion: "2.0.0")
    /// ```
    public static func current(
        appVersion: String? = nil,
        buildNumber: String? = nil
    ) -> EvaluationContext {
        let platform: String
        #if os(iOS)
            platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #elseif os(macOS)
            platform = "macOS"
        #elseif os(watchOS)
            platform = "watchOS"
        #elseif os(tvOS)
            platform = "tvOS"
        #elseif os(visionOS)
            platform = "visionOS"
        #else
            platform = "unknown"
        #endif

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let deviceModel: String
        #if os(iOS) || os(tvOS)
            deviceModel = UIDevice.current.model
        #elseif os(watchOS)
            deviceModel = WKInterfaceDevice.current().model
        #elseif os(macOS)
            deviceModel = "Mac"
        #elseif os(visionOS)
            deviceModel = "Apple Vision Pro"
        #else
            deviceModel = "unknown"
        #endif

        // Get app version and build from Info.plist if not provided
        let infoDictionary = Bundle.main.infoDictionary
        let resolvedAppVersion =
            appVersion ?? (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let resolvedBuildNumber =
            buildNumber ?? (infoDictionary?["CFBundleVersion"] as? String) ?? "1"

        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier

        return EvaluationContext(
            platform: platform,
            osVersion: osVersion,
            appVersion: resolvedAppVersion,
            buildNumber: resolvedBuildNumber,
            deviceModel: deviceModel,
            region: region,
            language: language
        )
    }
}
