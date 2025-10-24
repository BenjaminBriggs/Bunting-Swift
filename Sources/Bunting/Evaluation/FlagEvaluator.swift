import Foundation

/// Evaluates flags according to variant ordering and precedence rules
struct FlagEvaluator {
    let configuration: BuntingConfiguration
    let environment: BuntingEnvironment
    let context: EvaluationContext
    let localID: UUID
    let customAttributeResolver: EvaluationContext.CustomAttributeResolver

    /// Evaluates a flag and returns its effective value
    /// Algorithm:
    /// 1. Load environment config for the flag
    /// 2. Iterate variants in ascending order
    /// 3. For each variant:
    ///    - conditional: evaluate conditions → if all pass, return value
    ///    - test: check preconditions → bucket → return group value
    ///    - rollout: check preconditions → bucket → if ≤ percentage, return value
    /// 4. If no variant matches, return default
    func evaluate(flagKey: String) -> FlagValue? {
        guard let flag = configuration.flags[flagKey] else {
            return nil
        }

        let envConfig = flag.config(for: environment)
        let conditionEvaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: customAttributeResolver,
            cohorts: configuration.cohorts
        )

        // Sort variants by order (ascending)
        let sortedVariants = envConfig.variants.sorted { $0.order < $1.order }

        // Evaluate each variant in order
        for variant in sortedVariants {
            switch variant.type {
            case .conditional:
                if let conditions = variant.conditions,
                    conditionEvaluator.evaluateAll(conditions)
                {
                    // Conditional variants use the single 'value' property
                    if let value = variant.value {
                        return value
                    }
                }

            case .test:
                if let testName = variant.test,
                    let test = configuration.tests[testName],
                    let testValue = evaluateTest(
                        test, variant: variant, conditionEvaluator: conditionEvaluator)
                {
                    return testValue
                }

            case .rollout:
                if let rolloutName = variant.rollout,
                    let rollout = configuration.rollouts[rolloutName],
                    evaluateRollout(rollout, conditionEvaluator: conditionEvaluator)
                {
                    // Rollout variants use the single 'value' property
                    if let value = variant.value {
                        return value
                    }
                }
            }
        }

        // No variant matched, return default
        return envConfig.default
    }

    // MARK: - Test Evaluation

    private func evaluateTest(
        _ test: Test,
        variant: Variant,
        conditionEvaluator: ConditionEvaluator
    ) -> FlagValue? {
        // 1. Check test preconditions (test-level conditions)
        if test.conditions.isEmpty == false
            && conditionEvaluator.evaluateAll(test.conditions) == false
        {
            return nil
        }

        // 2. Compute bucket using test's salt (1-100)
        let bucket = Bucketing.bucket(salt: test.salt, localID: localID)

        // 3. Determine which group this bucket falls into
        // If test defines groups, use those for bucketing
        if let groupName = test.assignGroup(bucket: bucket) {
            // Return the value for this group from variant.values
            if let values = variant.values, let value = values[groupName] {
                return value
            }
        }

        // 4. Fallback: if no groups defined but variant has values dictionary,
        // try to map bucket to first available group (legacy support)
        if let values = variant.values, let firstValue = values.values.first {
            return firstValue
        }

        // 5. Final fallback: use variant.value if present (simple test without groups)
        return variant.value
    }

    // MARK: - Rollout Evaluation

    private func evaluateRollout(
        _ rollout: Rollout,
        conditionEvaluator: ConditionEvaluator
    ) -> Bool {
        // Check rollout preconditions
        if rollout.conditions.isEmpty == false
            && conditionEvaluator.evaluateAll(rollout.conditions) == false
        {
            return false
        }

        // Compute bucket
        let bucket = Bucketing.bucket(salt: rollout.salt, localID: localID)

        // Check if bucket qualifies for rollout
        return bucket <= rollout.percentage
    }
}
