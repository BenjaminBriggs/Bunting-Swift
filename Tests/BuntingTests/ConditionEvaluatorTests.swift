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
            language: "en"
        )
    }

    func testPlatformCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .platform,
            values: ["iOS", "iPadOS"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match iOS platform")
    }

    func testPlatformNotIn() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .platform,
            values: ["Android", "Web"],
            operator: .notIn
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should not be Android or Web")
    }

    func testAppVersionGreaterThanOrEqual() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .appVersion,
            values: ["2.0.0"],
            operator: .greaterThanOrEqual
        )

        XCTAssertTrue(evaluator.evaluate(condition), "2.5.0 should be >= 2.0.0")
    }

    func testAppVersionLessThan() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .appVersion,
            values: ["3.0.0"],
            operator: .lessThan
        )

        XCTAssertTrue(evaluator.evaluate(condition), "2.5.0 should be < 3.0.0")
    }

    func testBuildNumberComparison() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .buildNumber,
            values: ["50"],
            operator: .greaterThanOrEqual
        )

        XCTAssertTrue(evaluator.evaluate(condition), "100 should be >= 50")
    }

    func testRegionCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .region,
            values: ["US", "CA"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match US region")
    }

    func testLanguageCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .language,
            values: ["en", "fr"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Language 'en' should be in [en, fr]")
    }

    func testCustomAttribute() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { attribute in
                return attribute == "is_premium"
            }
        )

        let condition = Condition(
            type: .customAttribute,
            values: ["is_premium"],
            operator: .custom
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should resolve custom attribute")
    }

    func testAllConditionsPass() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let conditions = [
            Condition(type: .platform, values: ["iOS"], operator: .in),
            Condition(type: .region, values: ["US"], operator: .in),
        ]

        XCTAssertTrue(evaluator.evaluateAll(conditions), "All conditions should pass")
    }

    func testAnyConditionFails() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let conditions = [
            Condition(type: .platform, values: ["iOS"], operator: .in),
            Condition(type: .region, values: ["GB"], operator: .in),
        ]

        XCTAssertFalse(evaluator.evaluateAll(conditions), "Should fail when any condition fails")
    }
}
