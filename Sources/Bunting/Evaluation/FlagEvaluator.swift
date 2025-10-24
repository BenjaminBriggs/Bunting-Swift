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
                    return variant.value
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
                    return variant.value
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
        // Check test preconditions
        if test.conditions.isEmpty == false
            && conditionEvaluator.evaluateAll(test.conditions) == false
        {
            return nil
        }

        // For v1, test variants simply return their value if preconditions pass
        // Future versions will implement group-based bucketing with test.salt
        // _ = Bucketing.bucket(salt: test.salt, localID: localID)

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
