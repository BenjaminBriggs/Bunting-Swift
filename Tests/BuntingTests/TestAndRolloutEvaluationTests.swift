import Foundation
import Testing

@testable import Bunting

@Suite("Test and Rollout Evaluation")
struct TestAndRolloutEvaluationTests {

    // MARK: - Test Variant with Group Bucketing

    @Test("Test variant assigns users to groups correctly")
    func testVariantGroupAssignment() async throws {
        // Create a 50/50 split test
        let test = Test(
            name: "Button Test",
            description: "Test button colors",
            type: "test",
            salt: "button-test-salt",
            conditions: [],
            groups: [
                TestGroup(name: "control", percentage: 50),
                TestGroup(name: "variant", percentage: 50),
            ]
        )

        let variant = Variant(
            type: .test,
            order: 1,
            value: nil,
            values: [
                "control": .boolean(false),
                "variant": .boolean(true),
            ],
            conditions: nil,
            test: "button_test",
            rollout: nil
        )

        let flag = Flag(
            type: .boolean,
            description: nil,
            development: EnvironmentConfig(default: .boolean(false), variants: [variant]),
            staging: EnvironmentConfig(default: .boolean(false), variants: []),
            production: EnvironmentConfig(default: .boolean(false), variants: [])
        )

        let config = BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: ["test_flag": flag],
            cohorts: [:],
            tests: ["button_test": test],
            rollouts: [:]
        )

        let context = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            region: "US",
            locale: "en-US"
        )

        // Test with 100 different UUIDs - should get roughly 50/50 split
        var controlCount = 0
        var variantCount = 0

        for _ in 0..<100 {
            let localID = UUID()
            let evaluator = FlagEvaluator(
                configuration: config,
                environment: .development,
                context: context,
                localID: localID,
                customAttributeResolver: { _ in false }
            )

            if case .boolean(let value) = evaluator.evaluate(flagKey: "test_flag") {
                if value {
                    variantCount += 1
                } else {
                    controlCount += 1
                }
            }
        }

        // With 50/50 split, expect 30-70 range for each (allowing variance)
        #expect(controlCount >= 30 && controlCount <= 70)
        #expect(variantCount >= 30 && variantCount <= 70)
    }

    @Test("Test variant is deterministic for same UUID")
    func testVariantDeterministic() async throws {
        let test = Test(
            name: "Feature Test",
            description: nil,
            type: "test",
            salt: "feature-salt",
            conditions: [],
            groups: [
                TestGroup(name: "control", percentage: 50),
                TestGroup(name: "variant", percentage: 50),
            ]
        )

        let variant = Variant(
            type: .test,
            order: 1,
            value: nil,
            values: [
                "control": .string("old"),
                "variant": .string("new"),
            ],
            conditions: nil,
            test: "feature_test",
            rollout: nil
        )

        let flag = Flag(
            type: .string,
            description: nil,
            development: EnvironmentConfig(default: .string("default"), variants: [variant]),
            staging: EnvironmentConfig(default: .string("default"), variants: []),
            production: EnvironmentConfig(default: .string("default"), variants: [])
        )

        let config = BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: ["feature": flag],
            cohorts: [:],
            tests: ["feature_test": test],
            rollouts: [:]
        )

        let context = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            region: "US",
            locale: "en-US"
        )

        let localID = UUID()

        let evaluator = FlagEvaluator(
            configuration: config,
            environment: .development,
            context: context,
            localID: localID,
            customAttributeResolver: { _ in false }
        )

        // Same UUID should always return same result
        let result1 = evaluator.evaluate(flagKey: "feature")
        let result2 = evaluator.evaluate(flagKey: "feature")
        let result3 = evaluator.evaluate(flagKey: "feature")

        // Convert to strings for comparison
        let value1 = result1?.stringValue
        let value2 = result2?.stringValue
        let value3 = result3?.stringValue

        #expect(value1 == value2)
        #expect(value2 == value3)
        #expect(value1 != nil)
    }

    @Test("Test variant respects preconditions")
    func testVariantPreconditions() async throws {
        let test = Test(
            name: "iOS Only Test",
            description: nil,
            type: "test",
            salt: "ios-test-salt",
            conditions: [
                Condition(
                    id: "platform-ios",
                    type: .platform,
                    values: ["iOS"],
                    operator: .in
                )
            ],
            groups: [
                TestGroup(name: "control", percentage: 50),
                TestGroup(name: "variant", percentage: 50),
            ]
        )

        let variant = Variant(
            type: .test,
            order: 1,
            value: nil,
            values: [
                "control": .boolean(false),
                "variant": .boolean(true),
            ],
            conditions: nil,
            test: "ios_only_test",
            rollout: nil
        )

        let flag = Flag(
            type: .boolean,
            description: nil,
            development: EnvironmentConfig(default: .boolean(false), variants: [variant]),
            staging: EnvironmentConfig(default: .boolean(false), variants: []),
            production: EnvironmentConfig(default: .boolean(false), variants: [])
        )

        let config = BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: ["ios_feature": flag],
            cohorts: [:],
            tests: ["ios_only_test": test],
            rollouts: [:]
        )

        // Test on macOS - should fail precondition
        let macContext = EvaluationContext(
            platform: "macOS",
            osVersion: "15.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "Mac",
            region: "US",
            locale: "en-US"
        )

        let evaluator1 = FlagEvaluator(
            configuration: config,
            environment: .development,
            context: macContext,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        let macResult = evaluator1.evaluate(flagKey: "ios_feature")
        #expect(macResult == .boolean(false))  // Should return default

        // Test on iOS - should pass precondition
        let iosContext = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            region: "US",
            locale: "en-US"
        )

        let evaluator2 = FlagEvaluator(
            configuration: config,
            environment: .development,
            context: iosContext,
            localID: UUID(),
            customAttributeResolver: { _ in false }
        )

        let iosResult = evaluator2.evaluate(flagKey: "ios_feature")
        // Should return either true or false (from test groups), not default
        #expect(iosResult != nil)
    }

    // MARK: - Rollout Variant Evaluation

    @Test("Rollout variant respects percentage")
    func rolloutPercentage() async throws {
        let rollout = Rollout(
            name: "25% Rollout",
            description: nil,
            type: "rollout",
            salt: "rollout-salt",
            conditions: [],
            percentage: 25
        )

        let variant = Variant(
            type: .rollout,
            order: 1,
            value: .boolean(true),
            values: nil,
            conditions: nil,
            test: nil,
            rollout: "test_rollout"
        )

        let flag = Flag(
            type: .boolean,
            description: nil,
            development: EnvironmentConfig(default: .boolean(false), variants: [variant]),
            staging: EnvironmentConfig(default: .boolean(false), variants: []),
            production: EnvironmentConfig(default: .boolean(false), variants: [])
        )

        let config = BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: ["rollout_flag": flag],
            cohorts: [:],
            tests: [:],
            rollouts: ["test_rollout": rollout]
        )

        let context = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            region: "US",
            locale: "en-US"
        )

        var inRolloutCount = 0
        for _ in 0..<100 {
            let evaluator = FlagEvaluator(
                configuration: config,
                environment: .development,
                context: context,
                localID: UUID(),
                customAttributeResolver: { _ in false }
            )

            if case .boolean(let value) = evaluator.evaluate(flagKey: "rollout_flag"), value == true
            {
                inRolloutCount += 1
            }
        }

        // With 25% rollout, expect 15-35 out of 100
        #expect(inRolloutCount >= 15 && inRolloutCount <= 35)
    }

    @Test("Rollout is deterministic")
    func rolloutDeterministic() async throws {
        let rollout = Rollout(
            name: "50% Rollout",
            description: nil,
            type: "rollout",
            salt: "stable-salt",
            conditions: [],
            percentage: 50
        )

        let variant = Variant(
            type: .rollout,
            order: 1,
            value: .integer(42),
            values: nil,
            conditions: nil,
            test: nil,
            rollout: "stable_rollout"
        )

        let flag = Flag(
            type: .integer,
            description: nil,
            development: EnvironmentConfig(default: .integer(0), variants: [variant]),
            staging: EnvironmentConfig(default: .integer(0), variants: []),
            production: EnvironmentConfig(default: .integer(0), variants: [])
        )

        let config = BuntingConfiguration(
            schemaVersion: 1,
            configVersion: "2025-01-01.1",
            publishedAt: Date(),
            appIdentifier: "test-app",
            flags: ["rollout_number": flag],
            cohorts: [:],
            tests: [:],
            rollouts: ["stable_rollout": rollout]
        )

        let context = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            region: "US",
            locale: "en-US"
        )

        let localID = UUID()
        let evaluator = FlagEvaluator(
            configuration: config,
            environment: .development,
            context: context,
            localID: localID,
            customAttributeResolver: { _ in false }
        )

        // Same UUID should always get same result
        let result1 = evaluator.evaluate(flagKey: "rollout_number")
        let result2 = evaluator.evaluate(flagKey: "rollout_number")
        let result3 = evaluator.evaluate(flagKey: "rollout_number")

        #expect(result1 == result2)
        #expect(result2 == result3)
    }
}

// Helper extension for FlagValue comparison
extension FlagValue: Equatable {
    public static func == (lhs: FlagValue, rhs: FlagValue) -> Bool {
        switch (lhs, rhs) {
        case (.boolean(let l), .boolean(let r)): return l == r
        case (.string(let l), .string(let r)): return l == r
        case (.integer(let l), .integer(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.date(let l), .date(let r)): return l == r
        case (.json(let l), .json(let r)): return l == r
        default: return false
        }
    }
}

// Helper extension to get string value from FlagValue
extension FlagValue {
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        default: return nil
        }
    }
}
