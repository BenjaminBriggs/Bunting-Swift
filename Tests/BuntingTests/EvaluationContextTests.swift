import Foundation
import Testing

@testable import Bunting

/// Verifies the two-axis derivation and reserved-attribute population of the
/// runtime context. Runs on the macOS test host, so `current()` must report the
/// desktop form factor and the `apple` manufacturer.
@Suite("EvaluationContext")
struct EvaluationContextTests {

    @Test("current() reports lowercase platform, desktop class, apple manufacturer on the macOS host")
    func currentDerivesTwoAxisOnHost() {
        let context = EvaluationContext.current(appVersion: "1.0.0", buildNumber: "1")
        #expect(context.platform == "macos")
        #expect(context.deviceClass == "desktop")
        #expect(context.reservedAttributes["manufacturer"] == "apple")
    }

    @Test("deviceClass participates in the memoization hash")
    func deviceClassChangesHash() {
        let phone = EvaluationContext(
            platform: "ios", osVersion: "18.0", appVersion: "1.0.0",
            buildNumber: "1", deviceModel: "iPhone", region: "US",
            language: "en", deviceClass: "phone", reservedAttributes: ["manufacturer": "apple"]
        )
        let tablet = EvaluationContext(
            platform: "ios", osVersion: "18.0", appVersion: "1.0.0",
            buildNumber: "1", deviceModel: "iPhone", region: "US",
            language: "en", deviceClass: "tablet", reservedAttributes: ["manufacturer": "apple"]
        )
        #expect(phone.computeHash() != tablet.computeHash())
    }

    @Test("reservedAttributes participate in the memoization hash")
    func reservedAttributesChangeHash() {
        let base = EvaluationContext(
            platform: "android", osVersion: "15", appVersion: "1.0.0",
            buildNumber: "1", deviceModel: "Pixel 8", region: "US",
            language: "en", deviceClass: "phone", reservedAttributes: ["manufacturer": "google"]
        )
        let other = EvaluationContext(
            platform: "android", osVersion: "15", appVersion: "1.0.0",
            buildNumber: "1", deviceModel: "SM-S911", region: "US",
            language: "en", deviceClass: "phone", reservedAttributes: ["manufacturer": "samsung"]
        )
        #expect(base.computeHash() != other.computeHash())
    }
}
