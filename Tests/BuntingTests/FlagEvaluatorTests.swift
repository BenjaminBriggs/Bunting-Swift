import Foundation
import Testing

@testable import Bunting

/// Direct coverage of `FlagEvaluator`'s variant-ordering and fallback contract.
/// Test/rollout bucketing coverage (group assignment, percentage gating,
/// determinism) already lives in `TestAndRolloutEvaluationTests.swift`; this
/// file focuses on conditional-variant precedence, environment selection,
/// and deprecated-flag handling.
@Suite("FlagEvaluator")
struct FlagEvaluatorTests {

    private static let context = EvaluationContext(
        platform: "ios",
        osVersion: "18.0",
        appVersion: "1.0.0",
        buildNumber: "1",
        deviceModel: "iPhone",
        region: "US",
        language: "en"
    )

    private func makeConfig(flags: [String: Flag]) -> BuntingConfiguration {
        BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: flags,
            tests: [:],
            rollouts: [:]
        )
    }

    // MARK: - First-match-wins

    @Test("First matching conditional variant wins when both match")
    func firstMatchWinsWhenBothMatch() throws {
        let usVariant = Variant(
            type: .conditional,
            order: 1,
            value: .string("us-value"),
            values: nil,
            conditions: [Condition(type: .region, values: ["US"], operator: .in)],
            test: nil,
            rollout: nil
        )
        let alwaysVariant = Variant(
            type: .conditional,
            order: 2,
            value: .string("always-value"),
            values: nil,
            conditions: [Condition(type: .platform, values: ["ios"], operator: .in)],
            test: nil,
            rollout: nil
        )

        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(default: .string("default"), variants: [usVariant, alwaysVariant]),
            beta: EnvironmentConfig(default: .string("default"), variants: []),
            production: EnvironmentConfig(default: .string("default"), variants: [])
        )

        let evaluator = FlagEvaluator(
            configuration: makeConfig(flags: ["greeting": flag]),
            environment: .development,
            context: Self.context,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        #expect(evaluator.evaluate(flagKey: "greeting") == .string("us-value"))
    }

    @Test("Second variant matches when first does not")
    func secondVariantMatchesWhenFirstDoesNot() throws {
        let gbVariant = Variant(
            type: .conditional,
            order: 1,
            value: .string("gb-value"),
            values: nil,
            conditions: [Condition(type: .region, values: ["GB"], operator: .in)],
            test: nil,
            rollout: nil
        )
        let usVariant = Variant(
            type: .conditional,
            order: 2,
            value: .string("us-value"),
            values: nil,
            conditions: [Condition(type: .region, values: ["US"], operator: .in)],
            test: nil,
            rollout: nil
        )

        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(default: .string("default"), variants: [gbVariant, usVariant]),
            beta: EnvironmentConfig(default: .string("default"), variants: []),
            production: EnvironmentConfig(default: .string("default"), variants: [])
        )

        let evaluator = FlagEvaluator(
            configuration: makeConfig(flags: ["greeting": flag]),
            environment: .development,
            context: Self.context,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        #expect(evaluator.evaluate(flagKey: "greeting") == .string("us-value"))
    }

    @Test("No variant matches falls back to environment default")
    func noVariantMatchesReturnsDefault() throws {
        let gbVariant = Variant(
            type: .conditional,
            order: 1,
            value: .string("gb-value"),
            values: nil,
            conditions: [Condition(type: .region, values: ["GB"], operator: .in)],
            test: nil,
            rollout: nil
        )

        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(default: .string("default"), variants: [gbVariant]),
            beta: EnvironmentConfig(default: .string("default"), variants: []),
            production: EnvironmentConfig(default: .string("default"), variants: [])
        )

        let evaluator = FlagEvaluator(
            configuration: makeConfig(flags: ["greeting": flag]),
            environment: .development,
            context: Self.context,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        #expect(evaluator.evaluate(flagKey: "greeting") == .string("default"))
    }

    @Test("Non-contiguous order values are still respected")
    func nonContiguousOrderRespected() throws {
        // Deliberately out-of-order declaration and non-contiguous order
        // numbers (5, 100, 10) — the evaluator must sort by `order`, not by
        // declaration order or assume small contiguous integers.
        let order100 = Variant(
            type: .conditional,
            order: 100,
            value: .string("last"),
            values: nil,
            conditions: [],
            test: nil,
            rollout: nil
        )
        let order5 = Variant(
            type: .conditional,
            order: 5,
            value: .string("first"),
            values: nil,
            conditions: [],
            test: nil,
            rollout: nil
        )
        let order10 = Variant(
            type: .conditional,
            order: 10,
            value: .string("second"),
            values: nil,
            conditions: [],
            test: nil,
            rollout: nil
        )

        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(
                default: .string("default"), variants: [order100, order5, order10]),
            beta: EnvironmentConfig(default: .string("default"), variants: []),
            production: EnvironmentConfig(default: .string("default"), variants: [])
        )

        let evaluator = FlagEvaluator(
            configuration: makeConfig(flags: ["order_test": flag]),
            environment: .development,
            context: Self.context,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        #expect(evaluator.evaluate(flagKey: "order_test") == .string("first"))
    }

    // MARK: - Environment selection

    @Test("Environment selection picks the matching EnvironmentConfig")
    func environmentSelectionPicksCorrectConfig() throws {
        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(default: .string("dev-value"), variants: []),
            beta: EnvironmentConfig(default: .string("beta-value"), variants: []),
            production: EnvironmentConfig(default: .string("prod-value"), variants: [])
        )

        let config = makeConfig(flags: ["tier": flag])

        for (environment, expected) in [
            (BuntingEnvironment.development, "dev-value"),
            (BuntingEnvironment.beta, "beta-value"),
            (BuntingEnvironment.production, "prod-value"),
        ] {
            let evaluator = FlagEvaluator(
                configuration: config,
                environment: environment,
                context: Self.context,
                localID: UUID(),
                customAttributeResolver: { _ in false }
            )
            #expect(evaluator.evaluate(flagKey: "tier") == .string(expected))
        }
    }

    // MARK: - Deprecated flags

    @Test("Deprecated flags evaluate normally — deprecation is metadata only")
    func deprecatedFlagEvaluatesNormally() throws {
        let variant = Variant(
            type: .conditional,
            order: 1,
            value: .boolean(true),
            values: nil,
            conditions: [Condition(type: .platform, values: ["ios"], operator: .in)],
            test: nil,
            rollout: nil
        )

        let flag = Flag(
            type: .boolean,
            description: nil,
            development: EnvironmentConfig(default: .boolean(false), variants: [variant]),
            beta: EnvironmentConfig(default: .boolean(false), variants: []),
            production: EnvironmentConfig(default: .boolean(false), variants: []),
            deprecated: true
        )

        let evaluator = FlagEvaluator(
            configuration: makeConfig(flags: ["old_feature": flag]),
            environment: .development,
            context: Self.context,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        #expect(evaluator.evaluate(flagKey: "old_feature") == .boolean(true))
    }
}
