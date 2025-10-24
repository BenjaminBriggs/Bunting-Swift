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
@Observable
@MainActor
public final class Bunting {
    // MARK: - Public State (observable)

    public private(set) var environment: BuntingEnvironment
    public private(set) var configuration: BuntingConfiguration?
    public private(set) var cachedLocalID: UUID?

    // MARK: - Internal components (not observed)
    @ObservationIgnored private let identity: BuntingIdentity
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let overridesStore: OverridesStore
    @ObservationIgnored private let memoizationCache: MemoizationCache
    @ObservationIgnored private var overridesSnapshot: [String: OverrideValue] = [:]
    @ObservationIgnored private var overridesVersion: Int = 0
    @ObservationIgnored private var context: EvaluationContext
    @ObservationIgnored private var customAttributeResolver:
        EvaluationContext.CustomAttributeResolver

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
    public var localID: UUID { cachedLocalID ?? UUID() }

    // MARK: - Initialization
    private init(
        environment: BuntingEnvironment,
        context: EvaluationContext,
        keychainAccessGroup: String?,
        customAttributeResolver: @escaping EvaluationContext.CustomAttributeResolver
    ) throws {
        self.environment = environment
        self.context = context
        self.customAttributeResolver = customAttributeResolver

        // Initialize components
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
            }

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

    /// Configures the shared Bunting instance
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
    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        evaluateFlagSync(key, default: .boolean(defaultValue))?.boolValue ?? defaultValue
    }

    public func int(_ key: String, default defaultValue: Int) -> Int {
        evaluateFlagSync(key, default: .integer(defaultValue))?.intValue ?? defaultValue
    }

    public func double(_ key: String, default defaultValue: Double) -> Double {
        evaluateFlagSync(key, default: .double(defaultValue))?.doubleValue ?? defaultValue
    }

    public func string(_ key: String, default defaultValue: String) -> String {
        evaluateFlagSync(key, default: .string(defaultValue))?.stringValue ?? defaultValue
            ?? defaultValue
    }

    public func date(_ key: String, default defaultValue: Date) -> Date {
        evaluateFlagSync(key, default: .date(defaultValue))?.dateValue ?? defaultValue
    }

    public func jsonData(_ key: String) -> JSONData? {
        evaluateFlagSync(key, default: .json("{}"))?.jsonData
    }

    // MARK: - Core Evaluation (Sync from snapshots with memoization)
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

        // Try to get from cache (async access from sync context)
        // Note: We can't await here since this is sync, so we skip cache for now
        // Future: Consider making flag accessors async or using a sync cache wrapper

        let evaluator = FlagEvaluator(
            configuration: config,
            environment: environment,
            context: context,
            localID: localID,
            customAttributeResolver: customAttributeResolver
        )

        let result = evaluator.evaluate(flagKey: key) ?? defaultValue

        // Store in cache asynchronously
        Task {
            await memoizationCache.set(cacheKey, value: result)
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
    public func refresh() async {
        try? await configStore.refresh()
        let config = await configStore.getConfiguration()
        await MainActor.run {
            self.configuration = config
        }
        // Invalidate cache when configuration changes
        await memoizationCache.invalidateAll()
    }

    // MARK: - Overrides Access

    /// Get all current overrides
    /// Used by debug views to display override status
    public func getAllOverrides() -> [String: OverrideValue] {
        return overridesSnapshot
    }

    // MARK: - Overrides (sync API; persists asynchronously)
    public func setOverride(_ key: String, value: Any?) {
        if let value, let override = OverrideValue(value) {
            overridesSnapshot[key] = override
        } else {
            overridesSnapshot.removeValue(forKey: key)
        }
        overridesVersion += 1

        // Notify delegate
        eventsDelegate?.didChangeOverride(flagKey: key, value: value)

        Task {
            await overridesStore.setOverride(key, value: value)
            // Invalidate cache for this specific flag
            await memoizationCache.invalidate(flagKey: key)
        }
    }

    public func clearOverride(_ key: String) {
        overridesSnapshot.removeValue(forKey: key)
        overridesVersion += 1

        // Notify delegate
        eventsDelegate?.didChangeOverride(flagKey: key, value: nil)

        Task {
            await overridesStore.clearOverride(key)
            await memoizationCache.invalidate(flagKey: key)
        }
    }

    public func clearAllOverrides() {
        let clearedKeys = Array(overridesSnapshot.keys)
        overridesSnapshot.removeAll()
        overridesVersion += 1

        // Notify delegate for each cleared override
        for key in clearedKeys {
            eventsDelegate?.didChangeOverride(flagKey: key, value: nil)
        }

        Task {
            await overridesStore.clearAll()
            // Invalidate entire cache since all overrides changed
            await memoizationCache.invalidateAll()
        }
    }

    // MARK: - Identity
    public func resetIdentity() async throws {
        try await identity.resetIdentity()
        let id = try? await identity.getLocalID()
        await MainActor.run { self.cachedLocalID = id }
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
