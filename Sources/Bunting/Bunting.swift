import Foundation
import Observation

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
    @ObservationIgnored private var overridesSnapshot: [String: OverrideValue] = [:]
    @ObservationIgnored private var context: EvaluationContext
    @ObservationIgnored private var customAttributeResolver: EvaluationContext.CustomAttributeResolver

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

    // MARK: - Core Evaluation (Sync from snapshots)
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

        let evaluator = FlagEvaluator(
            configuration: config,
            environment: environment,
            context: context,
            localID: localID,
            customAttributeResolver: customAttributeResolver
        )
        return evaluator.evaluate(flagKey: key) ?? defaultValue
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
        await MainActor.run { self.configuration = config }
    }

    // MARK: - Overrides (sync API; persists asynchronously)
    public func setOverride(_ key: String, value: Any?) {
        if let value, let override = OverrideValue(value) {
            overridesSnapshot[key] = override
        } else {
            overridesSnapshot.removeValue(forKey: key)
        }
        Task { await overridesStore.setOverride(key, value: value) }
    }

    public func clearOverride(_ key: String) {
        overridesSnapshot.removeValue(forKey: key)
        Task { await overridesStore.clearOverride(key) }
    }

    public func clearAllOverrides() {
        overridesSnapshot.removeAll()
        Task { await overridesStore.clearAll() }
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
