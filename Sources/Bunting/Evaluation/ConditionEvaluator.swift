import Foundation

/// Evaluates conditions against runtime context
struct ConditionEvaluator {
    let context: EvaluationContext
    let customAttributeResolver: EvaluationContext.CustomAttributeResolver

    /// Evaluates a single condition
    func evaluate(_ condition: Condition) -> Bool {
        switch condition.type {
        case .osVersion:
            return evaluateVersion(condition, contextValue: context.osVersion)

        case .appVersion:
            return evaluateVersion(condition, contextValue: context.appVersion)

        case .buildNumber:
            return evaluateNumeric(condition, contextValue: Int(context.buildNumber) ?? 0)

        case .platform:
            return evaluateList(condition, contextValue: context.platform)

        case .deviceModel:
            return evaluateList(condition, contextValue: context.deviceModel)

        case .deviceClass:
            guard let deviceClass = context.deviceClass else { return false }
            return evaluateList(condition, contextValue: deviceClass)

        case .region:
            guard let region = context.region else { return false }
            return evaluateList(condition, contextValue: region)

        case .language:
            return evaluateList(condition, contextValue: context.language)

        case .customAttribute:
            guard let attributeName = condition.values.first else { return false }
            if let reservedValue = context.reservedAttributes[attributeName] {
                let accepted = condition.values.dropFirst()
                return accepted.contains(reservedValue)
            }
            return customAttributeResolver(attributeName)
        }
    }

    /// Evaluates all conditions (AND logic)
    func evaluateAll(_ conditions: [Condition]) -> Bool {
        return conditions.allSatisfy { evaluate($0) }
    }

    // MARK: - Version Comparison

    private func evaluateVersion(_ condition: Condition, contextValue: String) -> Bool {
        let contextVersion = parseVersion(contextValue)

        switch condition.operator {
        case .equals:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) == 0

        case .doesNotEquals:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) != 0

        case .greaterThan:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) > 0

        case .greaterThanOrEqual:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) >= 0

        case .lessThan:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) < 0

        case .lessThanOrEqual:
            let targetVersion = parseVersion(condition.values.first ?? "")
            return compareVersions(contextVersion, targetVersion) <= 0

        case .between:
            guard condition.values.count == 2 else { return false }
            let minVersion = parseVersion(condition.values[0])
            let maxVersion = parseVersion(condition.values[1])
            return compareVersions(contextVersion, minVersion) >= 0
                && compareVersions(contextVersion, maxVersion) <= 0

        default:
            return false
        }
    }

    private func parseVersion(_ versionString: String) -> [Int] {
        // Extract version numbers from strings like "Version 15.0 (Build 19A5261w)"
        let components = versionString.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return
            components
            .filter { $0.isEmpty == false }
            .compactMap { Int($0) }
    }

    private func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> Int {
        let maxLength = max(lhs.count, rhs.count)

        for i in 0..<maxLength {
            let left = i < lhs.count ? lhs[i] : 0
            let right = i < rhs.count ? rhs[i] : 0

            if left < right {
                return -1
            } else if left > right {
                return 1
            }
        }

        return 0  // Equal
    }

    // MARK: - Numeric Comparison

    private func evaluateNumeric(_ condition: Condition, contextValue: Int) -> Bool {
        switch condition.operator {
        case .equals:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue == target

        case .doesNotEquals:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue != target

        case .greaterThan:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue > target

        case .greaterThanOrEqual:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue >= target

        case .lessThan:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue < target

        case .lessThanOrEqual:
            guard let target = Int(condition.values.first ?? "") else { return false }
            return contextValue <= target

        case .between:
            guard condition.values.count == 2,
                let min = Int(condition.values[0]),
                let max = Int(condition.values[1])
            else { return false }
            return contextValue >= min && contextValue <= max

        default:
            return false
        }
    }

    // MARK: - List Comparison

    private func evaluateList(_ condition: Condition, contextValue: String) -> Bool {
        switch condition.operator {
        case .in:
            return condition.values.contains(contextValue)

        case .notIn:
            return condition.values.contains(contextValue) == false

        default:
            return false
        }
    }
}
