import Foundation
import Observation

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Typealias for JSON data returned by JSON-type flags
public typealias JSONData = Data

/// Main API for interacting with Bunting feature flags
///
/// `Bunting` is the primary interface for accessing feature flags in your application. It provides:
/// - **Synchronous flag evaluation** with automatic caching for high performance
/// - **Type-safe flag access** for bool, string, int, double, date, and JSON values
/// - **Override system** for testing and debugging
/// - **Observable state** for SwiftUI integration
/// - **Automatic updates** with periodic polling when app enters foreground
///
/// ## Usage
///
/// Configure the shared instance early in your app lifecycle:
///
/// ```swift
/// try Bunting.configure(environment: .production)
/// ```
///
/// Then access flags anywhere:
///
/// ```swift
/// let showNewFeature = Bunting.shared.bool("feature/new_design", default: false)
/// if let config = Bunting.shared.jsonData("settings/advanced") {
///     // Use JSON data
/// }
/// ```
///
/// ## Evaluation Algorithm
///
/// Flags are evaluated using an ordered variant system:
/// 1. **Overrides**: If a developer override exists, return immediately
/// 2. **Cache lookup**: Check memoization cache for recent evaluations
/// 3. **Variant evaluation**: Process variants in order (first match wins):
///    - **Conditional variants**: Check all conditions; if all pass, return value
///    - **Test variants**: Deterministically bucket users; return group value if matched
///    - **Rollout variants**: Deterministically bucket users; return value if percentage matched
/// 4. **Fallback**: Return environment default value
///
/// ## Performance
///
/// Flag access is optimized for speed:
/// - **Hot cache hits**: <2µs for repeated accesses with same conditions
/// - **Cache invalidation**: Automatic on configuration, environment, or override changes
/// - **Memoization**: Results cached per flag key, environment, context hash, and config version
///
/// ## Thread Safety
///
/// All public APIs are `@MainActor` isolated. Access is thread-safe from the main thread.
@Observable
@MainActor
public final class Bunting {
    /// The currently active environment (development, beta, or production)
    ///
    /// Changes to this property trigger flag re-evaluation and cache invalidation.
    /// Use ``setEnvironment(_:)`` to change this value.
    public private(set) var environment: BuntingEnvironment

    /// The current configuration loaded from the CDN
    ///
    /// `nil` if configuration hasn't been loaded yet or signature verification failed.
    /// When `nil`, flags return their default values (or cached values if available).
    /// Subscribe to configuration changes via ``eventsDelegate``.
    public private(set) var configuration: BuntingConfiguration?

    /// The device's local identifier loaded from Keychain
    ///
    /// `nil` if the local ID hasn't been loaded yet (check the first time you access flags).
    /// Used for deterministic user bucketing in tests and rollouts.
    /// Reset with ``resetIdentity()``.
    public private(set) var cachedLocalID: UUID?

    // MARK: - Internal components
    @ObservationIgnored private let identity: BuntingIdentity
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let overridesStore: OverridesStore
    @ObservationIgnored private let memoizationCache: MemoizationCache
    @ObservationIgnored private var overridesSnapshot: [String: OverrideValue] = [:]
    @ObservationIgnored private var overridesVersion: Int = 0
    @ObservationIgnored private var context: EvaluationContext
    @ObservationIgnored private var customAttributeResolver:
        EvaluationContext.CustomAttributeResolver
    @ObservationIgnored private var transientLocalID: UUID?

    // MARK: - Events Delegate

    /// Delegate to receive notifications about Bunting events
    ///
    /// Set this property to observe configuration fetch, signature verification,
    /// and override change events. The delegate is held as a weak reference.
    ///
    /// All delegate methods are called on the main actor.
    public weak var eventsDelegate: BuntingEventsDelegate? {
        didSet {
            // Update ConfigStore's delegate reference
            let delegate = eventsDelegate
            Task {
                await configStore.setEventsDelegate(delegate)
            }
        }
    }

    // MARK: - Derived Metadata
    public var configVersion: String? { configuration?.configVersion }
    public var publishedAt: Date? { configuration?.publishedAt }
    public var signatureVerified: Bool { configuration != nil }
    public var localID: UUID {
        if let id = cachedLocalID { return id }
        if let t = transientLocalID { return t }
        let temp = UUID()
        transientLocalID = temp
        return temp
    }

    /// A compact fingerprint of the flag configuration this client currently resolves.
    ///
    /// The fingerprint is a `<config_version>.<HEX>` string that encodes which
    /// resolution path every flag took for the active environment and this device's
    /// identity — not the values themselves. Pasted into the Bunting admin, it decodes
    /// back to each flag's resolved value and the reason it resolved that way, which
    /// makes it useful to attach to support tickets, logs, analytics, or QA reports.
    ///
    /// The string is returned as-is for the application to use however it wants.
    ///
    /// Returns `nil` until both a configuration and the device identity have loaded
    /// (the same precondition as flag evaluation). Local developer overrides are not
    /// reflected — the fingerprint describes the resolution the published artifact
    /// produces for this client.
    ///
    /// ```swift
    /// if let fingerprint = Bunting.shared.userFingerprint {
    ///     logger.info("config fingerprint: \(fingerprint)")
    /// }
    /// ```
    public var userFingerprint: String? {
        guard let config = configuration, let localID = cachedLocalID else {
            return nil
        }
        return ConfigFingerprint.compute(
            configuration: config,
            environment: environment,
            context: context,
            localID: localID,
            customAttributeResolver: customAttributeResolver
        )
    }

    // MARK: - Initialisation
    private init(
        environment: BuntingEnvironment,
        context: EvaluationContext,
        keychainAccessGroup: String?,
        customAttributeResolver: @escaping EvaluationContext.CustomAttributeResolver
    ) throws {
        self.environment = environment
        self.context = context
        self.customAttributeResolver = customAttributeResolver

        // Initialise components
        self.identity = BuntingIdentity(keychainAccessGroup: keychainAccessGroup)
        let bootstrapConfig = try BootstrapConfig.load()
        self.configStore = try ConfigStore(bootstrapConfig: bootstrapConfig)
        self.overridesStore = OverridesStore()
        self.memoizationCache = MemoizationCache()

        // Prime snapshots asynchronously
        Task { [weak self] in
            guard let self else { return }
            await self.configStore.loadCachedConfigIfNeeded()
            await self.overridesStore.loadOverridesIfNeeded()

            // Load initial snapshots
            let config = await self.configStore.getConfiguration()
            let overrides = await self.overridesStore.getAllOverrides()
            let id = try? await self.identity.getLocalID()

            await MainActor.run {
                self.configuration = config
                self.overridesSnapshot = overrides
                self.cachedLocalID = id
                self.transientLocalID = nil
            }

            #if DEBUG
                if id == nil {
                    assertionFailure(
                        "Bunting: Failed to read/write Local ID from Keychain. Ensure the app can access Keychain (entitlements, sandbox)."
                    )
                }
            #endif

            // Trigger an initial refresh (rate-limited by store)
            try? await self.configStore.refresh()
            let refreshed = await self.configStore.getConfiguration()
            await MainActor.run {
                self.configuration = refreshed
            }
        }

        // Setup foreground observer for periodic polling
        setupForegroundObserver()
    }

    // MARK: - Foreground Polling

    private func setupForegroundObserver() {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refresh()
                }
            }
        #elseif os(macOS)
            NotificationCenter.default.addObserver(
                forName: NSApplication.willBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refresh()
                }
            }
        #endif
    }

    // MARK: - Singleton

    private static var _shared: Bunting?

    /// Accesses the shared Bunting instance
    ///
    /// If no instance has been configured yet, creates one with default settings:
    /// - Environment: `.production`
    /// - Context: Current system information
    /// - No keychain access group
    /// - No custom attributes
    ///
    /// It's recommended to call ``configure(environment:context:keychainAccessGroup:customAttributes:)``
    /// early in your app lifecycle to use custom settings.
    ///
    /// - Returns: The shared `Bunting` instance
    public static var shared: Bunting {
        if let existing = _shared { return existing }
        // Create with default configuration
        let bunting = try! Bunting(
            environment: .production,
            context: .current(),
            keychainAccessGroup: nil,
            customAttributeResolver: { _ in false }
        )
        _shared = bunting
        return bunting
    }

    /// Configures the shared Bunting instance with custom settings
    ///
    /// Call this once at app startup to configure flag evaluation before accessing any flags.
    /// If not called, the shared instance will be auto-created with default settings.
    ///
    /// - Parameters:
    ///   - environment: The active environment (development, beta, or production)
    ///   - context: Runtime context including platform, OS version, app version, etc.
    ///     If `nil`, uses ``EvaluationContext/current()``
    ///   - keychainAccessGroup: Keychain access group for multi-app scenarios.
    ///     Leave `nil` for single-app usage
    ///   - customAttributes: Closure to evaluate custom flag conditions at runtime.
    ///     Return `true` if the named attribute is active for the current user
    ///
    /// - Throws: If bootstrap configuration cannot be loaded or Keychain access fails
    ///
    /// ## Example
    /// ```swift
    /// try Bunting.configure(
    ///     environment: .production,
    ///     context: .current(),
    ///     customAttributes: { attribute in
    ///         switch attribute {
    ///         case "pro_user": return currentUser.isPro
    ///         case "beta_tester": return currentUser.isBetaTester
    ///         default: return false
    ///         }
    ///     }
    /// )
    /// ```
    public static func configure(
        environment: BuntingEnvironment,
        context: EvaluationContext? = nil,
        keychainAccessGroup: String? = nil,
        customAttributes: @escaping EvaluationContext.CustomAttributeResolver = { _ in false }
    ) throws {
        let resolvedContext = context ?? .current()
        _shared = try Bunting(
            environment: environment,
            context: resolvedContext,
            keychainAccessGroup: keychainAccessGroup,
            customAttributeResolver: customAttributes
        )
    }

    // MARK: - Flag Access (Synchronous)

    /// Evaluates a boolean flag
    ///
    /// Returns the flag value if configured, otherwise returns the default value.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameters:
    ///   - key: The flag key to evaluate (e.g., "feature/new_design")
    ///   - defaultValue: Value to return if flag is not configured or evaluation fails
    /// - Returns: The flag value or default
    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        evaluateFlagSync(key, default: .boolean(defaultValue))?.boolValue ?? defaultValue
    }

    /// Evaluates an integer flag
    ///
    /// Returns the flag value if configured, otherwise returns the default value.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameters:
    ///   - key: The flag key to evaluate
    ///   - defaultValue: Value to return if flag is not configured or evaluation fails
    /// - Returns: The flag value or default
    public func int(_ key: String, default defaultValue: Int) -> Int {
        evaluateFlagSync(key, default: .integer(defaultValue))?.intValue ?? defaultValue
    }

    /// Evaluates a double (floating-point) flag
    ///
    /// Returns the flag value if configured, otherwise returns the default value.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameters:
    ///   - key: The flag key to evaluate
    ///   - defaultValue: Value to return if flag is not configured or evaluation fails
    /// - Returns: The flag value or default
    public func double(_ key: String, default defaultValue: Double) -> Double {
        evaluateFlagSync(key, default: .double(defaultValue))?.doubleValue ?? defaultValue
    }

    /// Evaluates a string flag
    ///
    /// Returns the flag value if configured, otherwise returns the default value.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameters:
    ///   - key: The flag key to evaluate
    ///   - defaultValue: Value to return if flag is not configured or evaluation fails
    /// - Returns: The flag value or default
    public func string(_ key: String, default defaultValue: String) -> String {
        evaluateFlagSync(key, default: .string(defaultValue))?.stringValue ?? defaultValue
            ?? defaultValue
    }

    /// Evaluates a date flag (ISO8601 formatted)
    ///
    /// Returns the flag value if configured, otherwise returns the default value.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameters:
    ///   - key: The flag key to evaluate
    ///   - defaultValue: Value to return if flag is not configured or evaluation fails
    /// - Returns: The flag value or default
    public func date(_ key: String, default defaultValue: Date) -> Date {
        evaluateFlagSync(key, default: .date(defaultValue))?.dateValue ?? defaultValue
    }

    /// Evaluates a JSON flag
    ///
    /// Returns UTF-8 encoded JSON data if the flag is configured, otherwise `nil`.
    /// Results are cached for repeated accesses with the same conditions.
    ///
    /// - Parameter key: The flag key to evaluate
    /// - Returns: UTF-8 encoded JSON data, or `nil` if not configured
    ///
    /// ## Example
    /// ```swift
    /// if let jsonData = Bunting.shared.jsonData("layout/sections") {
    ///     let sections = try JSONDecoder().decode([Section].self, from: jsonData)
    /// }
    /// ```
    public func jsonData(_ key: String) -> JSONData? {
        evaluateFlagSync(key, default: .json("{}"))?.jsonData
    }

    // MARK: - Core Evaluation (Sync from snapshots with memoization)
    /// Deprecated-flag reads already reported to the delegate, and the config
    /// version they were reported for (reset when a new config loads).
    private var reportedDeprecatedReads: Set<String> = []
    private var reportedDeprecatedConfigVersion: String?

    private func evaluateFlagSync(_ key: String, default defaultValue: FlagValue) -> FlagValue? {
        // Check override snapshot first
        if let overrideValue = overridesSnapshot[key],
            let coerced = convertOverrideToFlagValue(overrideValue, type: defaultValue.type)
        {
            return coerced
        }

        guard let config = configuration, let localID = cachedLocalID else {
            return defaultValue
        }

        // Check memoization cache
        let cacheKey = MemoizationCache.CacheKey(
            flagKey: key,
            environment: environment,
            contextHash: context.computeHash(),
            overridesVersion: overridesVersion,
            configVersion: config.configVersion
        )

        // Check cache for existing value
        if let cachedValue = memoizationCache.get(cacheKey) {
            return cachedValue
        }

        // Cache miss - evaluate the flag
        let evaluator = FlagEvaluator(
            configuration: config,
            environment: environment,
            context: context,
            localID: localID,
            customAttributeResolver: customAttributeResolver
        )

        let result = evaluator.evaluate(flagKey: key) ?? defaultValue

        // Store result in cache for future lookups
        memoizationCache.set(cacheKey, value: result)

        // Surface deprecated (archived) flag reads, once per key per loaded config.
        if config.flags[key]?.deprecated == true {
            if reportedDeprecatedConfigVersion != config.configVersion {
                reportedDeprecatedConfigVersion = config.configVersion
                reportedDeprecatedReads.removeAll()
            }
            if reportedDeprecatedReads.insert(key).inserted {
                eventsDelegate?.didReadDeprecatedFlag(flagKey: key)
            }
        }

        return result
    }

    private func convertOverrideToFlagValue(_ overrideValue: OverrideValue, type: FlagType)
        -> FlagValue?
    {
        switch (overrideValue, type) {
        case (.bool(let value), .boolean):
            return .boolean(value)
        case (.int(let value), .integer):
            return .integer(value)
        case (.double(let value), .double):
            return .double(value)
        case (.string(let value), .string):
            return .string(value)
        case (.string(let value), .json):
            return .json(value)
        case (.date(let value), .date):
            return .date(value)
        default:
            return nil
        }
    }

    // MARK: - Refresh (async, updates snapshots)

    /// Refreshes the feature flag configuration from the CDN
    ///
    /// Attempts to fetch the latest configuration from the CDN (subject to rate limiting).
    /// On success, updates ``configuration`` and invalidates the evaluation cache.
    /// On failure, silently retains the last known good configuration or falls back to bundled seed.
    ///
    /// This method is called automatically when the app enters the foreground.
    /// Call explicitly to force an immediate refresh.
    ///
    /// - Note: This is an async operation that does not block the main thread
    public func refresh() async {
        try? await configStore.refresh()
        let config = await configStore.getConfiguration()
        await MainActor.run {
            self.configuration = config
            // Invalidate cache when configuration changes
            self.memoizationCache.invalidateAll()
        }
    }

    // MARK: - Environment Switching

    /// Changes the active environment and invalidates cached evaluations
    ///
    /// Switching environments causes all flag evaluations to be re-computed on next access
    /// since flags may have different values per environment.
    ///
    /// - Parameter newEnvironment: The new environment to switch to
    public func setEnvironment(_ newEnvironment: BuntingEnvironment) {
        guard newEnvironment != environment else { return }
        environment = newEnvironment
        memoizationCache.invalidateAll()
    }

    // MARK: - Overrides Access

    /// Retrieves all currently active flag overrides
    ///
    /// Overrides take precedence over evaluated flag values and are useful for:
    /// - Testing different flag values in development
    /// - A/B testing specific feature variants
    /// - Debugging flag-related issues
    ///
    /// Overrides are persisted to UserDefaults and survive app restarts.
    ///
    /// - Returns: Dictionary mapping flag keys to override values
    public func getAllOverrides() -> [String: OverrideValue] {
        return overridesSnapshot
    }

    // MARK: - Overrides (sync API; persists asynchronously)

    /// Sets an override value for a specific flag
    ///
    /// Overrides take precedence over configured flag values. This is useful for:
    /// - Testing specific flag values during development
    /// - A/B testing variants without modifying configuration
    /// - Debugging configuration issues in production
    ///
    /// The override is persisted to UserDefaults immediately and survives app restarts.
    /// The evaluation cache is invalidated for this flag, causing it to be re-evaluated
    /// on next access with the new override value.
    ///
    /// - Parameters:
    ///   - key: The flag key to override (e.g., "feature/new_design")
    ///   - value: The override value. Can be any type matching your flag's expected type.
    ///     Pass `nil` to clear the override.
    ///
    /// ## Example
    /// ```swift
    /// // Override a boolean flag
    /// Bunting.shared.setOverride("feature/dark_mode", value: true)
    ///
    /// // Override a string flag
    /// Bunting.shared.setOverride("pricing/tier", value: "premium")
    ///
    /// // Clear the override
    /// Bunting.shared.setOverride("feature/dark_mode", value: nil)
    /// ```
    public func setOverride(_ key: String, value: Any?) {
        if let value, let override = OverrideValue(value) {
            overridesSnapshot[key] = override
        } else {
            overridesSnapshot.removeValue(forKey: key)
        }
        overridesVersion += 1

        // Notify delegate
        eventsDelegate?.didChangeOverride(flagKey: key, value: value)

        // Invalidate cache for this specific flag
        memoizationCache.invalidate(flagKey: key)

        Task {
            await overridesStore.setOverride(key, value: value)
        }
    }

    /// Clears an override for a specific flag
    ///
    /// Removes a flag override, causing the flag to return to its normal evaluated value.
    /// The evaluation cache is invalidated for this flag.
    ///
    /// - Parameter key: The flag key whose override should be cleared
    public func clearOverride(_ key: String) {
        overridesSnapshot.removeValue(forKey: key)
        overridesVersion += 1

        // Notify delegate
        eventsDelegate?.didChangeOverride(flagKey: key, value: nil)

        // Invalidate cache for this specific flag
        memoizationCache.invalidate(flagKey: key)

        Task {
            await overridesStore.clearOverride(key)
        }
    }

    /// Clears all active flag overrides at once
    ///
    /// Removes all overrides, causing all flags to return to their normal evaluated values.
    /// The entire evaluation cache is invalidated.
    ///
    /// - Note: Useful for resetting to a clean state after testing
    public func clearAllOverrides() {
        let clearedKeys = Array(overridesSnapshot.keys)
        overridesSnapshot.removeAll()
        overridesVersion += 1

        // Notify delegate for each cleared override
        for key in clearedKeys {
            eventsDelegate?.didChangeOverride(flagKey: key, value: nil)
        }

        // Invalidate entire cache since all overrides changed
        memoizationCache.invalidateAll()

        Task {
            await overridesStore.clearAll()
        }
    }

    // MARK: - Identity

    /// Resets the device's local identifier and invalidates cached flag evaluations
    ///
    /// Generates a new device identifier and stores it in Keychain. This affects:
    /// - User bucketing for test variants (group assignment changes)
    /// - Rollout percentage calculations (user may qualify for different rollouts)
    /// - Any other flag conditions dependent on device identity
    ///
    /// All cached flag evaluations are invalidated since the new identity will produce
    /// different bucketing results. Flags are re-evaluated on next access.
    ///
    /// - Throws: If Keychain operations fail
    ///
    /// - Note: This is useful for testing to simulate a new device or user reset scenario
    public func resetIdentity() async throws {
        try await identity.resetIdentity()
        let id = try? await identity.getLocalID()
        await MainActor.run {
            self.cachedLocalID = id
            self.transientLocalID = nil
            // Invalidate cache since localID affects bucketing for tests and rollouts
            self.memoizationCache.invalidateAll()
        }
    }
}

// MARK: - FlagValue Helpers
extension FlagValue {
    var type: FlagType {
        switch self {
        case .boolean: return .boolean
        case .string: return .string
        case .integer: return .integer
        case .double: return .double
        case .date: return .date
        case .json: return .json
        }
    }

    var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var dateValue: Date? {
        if case .date(let value) = self {
            return value
        }
        return nil
    }

    var jsonData: Data? {
        if case .json(let value) = self {
            return value.data(using: .utf8)
        }
        return nil
    }
}
