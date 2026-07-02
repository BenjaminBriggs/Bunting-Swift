import XCTest

@testable import Bunting

final class ConditionEvaluatorTests: XCTestCase {
    var context: EvaluationContext!

    override func setUp() {
        super.setUp()
        context = EvaluationContext(
            platform: "ios",
            osVersion: "18.0",
            appVersion: "2.5.0",
            buildNumber: "100",
            deviceModel: "iPhone",
            region: "US",
            language: "en",
            deviceClass: "phone"
        )
    }

    func testPlatformCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .platform,
            values: ["ios"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match ios platform")
    }

    func testPlatformNotIn() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .platform,
            values: ["android", "web"],
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
            Condition(type: .platform, values: ["ios"], operator: .in),
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
            Condition(type: .platform, values: ["ios"], operator: .in),
            Condition(type: .region, values: ["GB"], operator: .in),
        ]

        XCTAssertFalse(evaluator.evaluateAll(conditions), "Should fail when any condition fails")
    }

    func testVisionOSPlatformCondition() {
        // EvaluationContext.current() can't be exercised for visionOS outside
        // that platform's toolchain, so this covers the condition-matching
        // path with an injected context (see EvaluationContext.current()'s
        // #if os(visionOS) branch for the platform derivation itself).
        let visionContext = EvaluationContext(
            platform: "visionos",
            osVersion: "2.0",
            appVersion: "1.0.0",
            buildNumber: "1",
            deviceModel: "Apple Vision Pro",
            region: "US",
            language: "en",
            deviceClass: "headset",
            reservedAttributes: ["manufacturer": "apple"]
        )
        let evaluator = ConditionEvaluator(
            context: visionContext,
            customAttributeResolver: { _ in false }
        )

        let condition = Condition(
            type: .platform,
            values: ["visionos"],
            operator: .in
        )

        XCTAssertTrue(evaluator.evaluate(condition), "Should match visionOS platform")
    }

    func testDeviceClassCondition() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { _ in false }
        )
        let condition = Condition(
            type: .deviceClass,
            values: ["phone", "tablet"],
            operator: .in
        )
        XCTAssertTrue(evaluator.evaluate(condition), "iPhone context (phone) should match [phone, tablet]")
    }

    func testDeviceClassAbsentDoesNotMatch() {
        let webContext = EvaluationContext(
            platform: "web", osVersion: "1", appVersion: "1.0.0", buildNumber: "1",
            deviceModel: "unknown", region: "US", language: "en",
            deviceClass: nil, reservedAttributes: [:]
        )
        let evaluator = ConditionEvaluator(
            context: webContext,
            customAttributeResolver: { _ in false }
        )
        let inCondition = Condition(type: .deviceClass, values: ["desktop"], operator: .in)
        let notInCondition = Condition(type: .deviceClass, values: ["desktop"], operator: .notIn)
        XCTAssertFalse(evaluator.evaluate(inCondition), "Absent device_class must not match `in`")
        XCTAssertFalse(evaluator.evaluate(notInCondition), "Absent device_class must not match `not_in`")
    }

    func testReservedManufacturerAttribute() {
        let appleContext = EvaluationContext(
            platform: "ios", osVersion: "18.0", appVersion: "2.5.0", buildNumber: "100",
            deviceModel: "iPhone", region: "US", language: "en",
            deviceClass: "phone", reservedAttributes: ["manufacturer": "apple"]
        )
        // Resolver returns false for everything: proves the reserved attribute is
        // resolved internally, not delegated to the app.
        let evaluator = ConditionEvaluator(
            context: appleContext,
            customAttributeResolver: { _ in false }
        )
        let matches = Condition(type: .customAttribute, values: ["manufacturer", "apple"], operator: .custom)
        let misses = Condition(type: .customAttribute, values: ["manufacturer", "samsung"], operator: .custom)
        XCTAssertTrue(evaluator.evaluate(matches), "manufacturer apple should match [apple]")
        XCTAssertFalse(evaluator.evaluate(misses), "manufacturer apple should not match [samsung]")
    }

    func testReservedAttributeAbsentNeverDelegatesToResolver() {
        // Context populates no reserved attributes at all (e.g. an unrecognized
        // platform). A resolver that would say "yes" to everything must never be
        // consulted for a reserved name: absent means no match, full stop.
        let noReservedContext = EvaluationContext(
            platform: "web", osVersion: "1", appVersion: "1.0.0", buildNumber: "1",
            deviceModel: "unknown", region: "US", language: "en",
            deviceClass: nil, reservedAttributes: [:]
        )
        nonisolated(unsafe) var resolverCalled = false
        let evaluator = ConditionEvaluator(
            context: noReservedContext,
            customAttributeResolver: { _ in
                resolverCalled = true
                return true
            }
        )
        let condition = Condition(type: .customAttribute, values: ["manufacturer", "apple"], operator: .custom)
        XCTAssertFalse(evaluator.evaluate(condition), "Absent reserved attribute must not match")
        XCTAssertFalse(resolverCalled, "App resolver must never be called for a reserved attribute name")
    }

    func testNonReservedCustomAttributeStillDelegates() {
        let evaluator = ConditionEvaluator(
            context: context,
            customAttributeResolver: { $0 == "is_premium" }
        )
        let condition = Condition(type: .customAttribute, values: ["is_premium"], operator: .custom)
        XCTAssertTrue(evaluator.evaluate(condition), "Non-reserved attribute must still hit the app resolver")
    }
}
