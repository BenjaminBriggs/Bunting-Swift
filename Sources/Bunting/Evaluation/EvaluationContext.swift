import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

/// Runtime context for flag evaluation
public struct EvaluationContext: Sendable, Hashable {
    public let platform: String
    public let osVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let deviceModel: String
    public let region: String?
    public let locale: String

    public init(
        platform: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        region: String?,
        locale: String
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.region = region
        self.locale = locale
    }

    /// Custom attributes resolver (not stored in context, passed separately)
    public typealias CustomAttributeResolver = @Sendable (String) -> Bool

    /// Computes a hash of the context for memoization
    /// This hash includes all stable runtime inputs that affect flag evaluation
    public func computeHash() -> Int {
        var hasher = Hasher()
        hasher.combine(platform)
        hasher.combine(osVersion)
        hasher.combine(appVersion)
        hasher.combine(buildNumber)
        hasher.combine(deviceModel)
        hasher.combine(region)
        hasher.combine(locale)
        return hasher.finalize()
    }

    /// Creates an evaluation context with current system information
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
        #else
            deviceModel = "unknown"
        #endif

        // Get app version and build from Info.plist if not provided
        let infoDictionary = Bundle.main.infoDictionary
        let resolvedAppVersion =
            appVersion ?? (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let resolvedBuildNumber =
            buildNumber ?? (infoDictionary?["CFBundleVersion"] as? String) ?? "1"

        let locale = Locale.current.identifier
        let region = Locale.current.region?.identifier

        return EvaluationContext(
            platform: platform,
            osVersion: osVersion,
            appVersion: resolvedAppVersion,
            buildNumber: resolvedBuildNumber,
            deviceModel: deviceModel,
            region: region,
            locale: locale
        )
    }
}
