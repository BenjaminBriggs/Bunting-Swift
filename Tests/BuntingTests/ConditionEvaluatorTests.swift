import XCTest

@testable import Bunting

final class ConditionEvaluatorTests: XCTestCase {
    var context: EvaluationContext!

    override func setUp() {
        super.setUp()
        context = EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "2.5.0",
            buildNumber: "100",
            deviceModel: "iPhone",
            region: "US",
            locale: "en_US"
        )
    }

    func testPlatformCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "platform-ios",
            type: .platform,
            values: ["iOS", "iPadOS"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match iOS platform")
    }

    func testPlatformNotIn() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "platform-not-android",
            type: .platform,
            values: ["Android", "Web"],
            operator: .notIn
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should not be Android or Web")
    }

    func testAppVersionGreaterThanOrEqual() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "version-gte",
            type: .appVersion,
            values: ["2.0.0"],
            operator: .greaterThanOrEqual
        )

        XCTAssertTrue(evaluator.evaluate(condition), "2.5.0 should be >= 2.0.0")
    }

    func testAppVersionLessThan() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "version-lt",
            type: .appVersion,
            values: ["3.0.0"],
            operator: .lessThan
        )

        XCTAssertTrue(evaluator.evaluate(condition), "2.5.0 should be < 3.0.0")
    }

    func testBuildNumberComparison() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "build-gte",
            type: .buildNumber,
            values: ["50"],
            operator: .greaterThanOrEqual
        )

        XCTAssertTrue(evaluator.evaluate(condition), "100 should be >= 50")
    }

    func testRegionCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "region-us",
            type: .region,
            values: ["US", "CA"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match US region")
    }

    func testLocalePrefix() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let condition = Condition(
            id: "locale-en",
            type: .locale,
            values: ["en"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "en_US should match en prefix")
    }

    func testCustomAttribute() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { attribute in
                return attribute == "is_premium"
            },
            cohorts: [:]
        )

        let condition = Condition(
            id: "custom-premium",
            type: .customAttribute,
            values: ["is_premium"],
            operator: .custom
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should resolve custom attribute")
    }

    func testCohortEvaluation() {
        let cohort = Cohort(
            name: "beta_users",
            description: "Beta testers",
            conditions: [
                Condition(
                    id: "version-gte",
                    type: .appVersion,
                    values: ["2.0.0"],
                    operator: .greaterThanOrEqual
                )
            ]
        )

        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: ["beta_users": cohort]
        )

        let condition = Condition(
            id: "in-beta",
            type: .cohort,
            values: ["beta_users"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should be in beta_users cohort")
    }

    func testAllConditionsPass() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let conditions = [
            Condition(id: "1", type: .platform, values: ["iOS"], operator: .in),
            Condition(id: "2", type: .region, values: ["US"], operator: .in),
        ]

        XCTAssertTrue(evaluator.evaluateAll(conditions), "All conditions should pass")
    }

    func testAnyConditionFails() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false },
            cohorts: [:]
        )

        let conditions = [
            Condition(id: "1", type: .platform, values: ["iOS"], operator: .in),
            Condition(id: "2", type: .region, values: ["GB"], operator: .in),
        ]

        XCTAssertFalse(evaluator.evaluateAll(conditions), "Should fail when any condition fails")
    }
}
