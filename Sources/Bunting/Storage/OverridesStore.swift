import Foundation

/// Sendable wrapper for override values
public enum OverrideValue: Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case date(Date)

    init?(_ value: Any) {
        if let bool = value as? Bool {
            self = .bool(bool)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let string = value as? String {
            self = .string(string)
        } else if let date = value as? Date {
            self = .date(date)
        } else {
            return nil
        }
    }

    var asAny: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .date(let value): return value
        }
    }
}

/// Manages local flag overrides for debugging and testing
actor OverridesStore {
    private var overrides: [String: OverrideValue] = [:]
    private let userDefaultsKey = "bunting.overrides"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Loads overrides from UserDefaults (should be called after init)
    func loadOverridesIfNeeded() {
        guard overrides.isEmpty else { return }
        loadOverrides()
    }

    // MARK: - Public API

    /// Sets an override value for a flag
    func setOverride(_ key: String, value: OverrideValue?) {
        if let value {
            overrides[key] = value
        } else {
            overrides.removeValue(forKey: key)
        }
        saveOverrides()
    }

    /// Gets the override value for a flag, if any
    func getOverride(_ key: String) -> OverrideValue? {
        return overrides[key]
    }

    /// Clears the override for a specific flag
    func clearOverride(_ key: String) {
        overrides.removeValue(forKey: key)
        saveOverrides()
    }

    /// Clears all overrides
    func clearAll() {
        overrides.removeAll()
        saveOverrides()
    }

    /// Returns all current overrides
    func getAllOverrides() -> [String: OverrideValue] {
        return overrides
    }

    // MARK: - Persistence

    private func loadOverrides() {
        if let saved = userDefaults.dictionary(forKey: userDefaultsKey) {
            for (key, value) in saved {
                if let overrideValue = OverrideValue(value) {
                    overrides[key] = overrideValue
                }
            }
        }
    }

    private func saveOverrides() {
        let dict = overrides.mapValues { $0.asAny }
        userDefaults.set(dict, forKey: userDefaultsKey)
    }
}
