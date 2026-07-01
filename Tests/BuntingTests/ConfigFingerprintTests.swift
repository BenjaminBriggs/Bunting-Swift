import Foundation
import Testing

@testable import Bunting

/// Cross-validates the SDK fingerprint encoder against the admin reference codec
/// (`bunting-admin/src/lib/fingerprint.ts`) using the same published vectors that
/// `bunting-admin/tests/unit/fingerprint.test.ts` asserts.
struct ConfigFingerprintTests {

    // A fixed device identity; irrelevant for flags without tests/rollouts.
    private let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func context(buildNumber: String = "1000") -> EvaluationContext {
        EvaluationContext(
            platform: "iOS",
            osVersion: "18.0",
            appVersion: "2.0.0",
            buildNumber: buildNumber,
            deviceModel: "iPhone16,2",
            region: "US",
            language: "en"
        )
    }

    private func decode(_ json: String) throws -> BuntingConfiguration {
        try JSONDecoder().decode(BuntingConfiguration.self, from: Data(json.utf8))
    }

    // The sample artifact from the admin test suite: one bool flag whose production
    // environment has a single conditional variant (build_number >= 1234).
    private let sampleJSON = """
        {
          "schema_version": 1,
          "config_version": "2026-06-17.2",
          "published_at": "2026-06-17T22:13:33.607Z",
          "app_identifier": "feast-ios",
          "flags": {
            "show_store": {
              "type": "bool",
              "description": "",
              "development": { "default": true, "variants": [] },
              "beta": { "default": false, "variants": [] },
              "production": {
                "default": false,
                "variants": [
                  { "type": "conditional", "order": 1, "value": true,
                    "conditions": [
                      { "id": "x", "type": "build_number", "values": ["1234"],
                        "operator": "greater_than_or_equal" }
                    ] }
                ]
              }
            }
          },
          "tests": {},
          "rollouts": {}
        }
        """

    // MARK: - Primitives

    @Test func bitWidthMatchesReference() {
        #expect(ConfigFingerprint.bitWidth(1) == 0)
        #expect(ConfigFingerprint.bitWidth(2) == 1)
        #expect(ConfigFingerprint.bitWidth(3) == 2)
        #expect(ConfigFingerprint.bitWidth(4) == 2)
        #expect(ConfigFingerprint.bitWidth(5) == 3)
        #expect(ConfigFingerprint.bitWidth(8) == 3)
        #expect(ConfigFingerprint.bitWidth(9) == 4)
    }

    @Test func crc8MatchesDocumentedExamples() {
        #expect(ConfigFingerprint.crc8([0x1A]) == 0x46)
        #expect(ConfigFingerprint.crc8([0x10]) == 0x70)
        #expect(ConfigFingerprint.crc8([0x14]) == 0x6C)
        #expect(ConfigFingerprint.crc8([0x18]) == 0x48)
    }

    @Test func environmentIndexes() {
        #expect(BuntingEnvironment.development.fingerprintIndex == 0)
        #expect(BuntingEnvironment.beta.fingerprintIndex == 1)
        #expect(BuntingEnvironment.production.fingerprintIndex == 2)
    }

    // MARK: - Encoder cross-vectors (byte-for-byte vs. admin)

    @Test func encodeProducesDocumentedCodes() {
        // development / beta: show_store has a single path → 0 bits.
        #expect(
            ConfigFingerprint.encode(
                configVersion: "2026-06-17.2", environmentIndex: 0,
                flagWidthsSortedByKey: [(key: "show_store", width: 0)], selections: [:]
            ) == "2026-06-17.2.1070")
        #expect(
            ConfigFingerprint.encode(
                configVersion: "2026-06-17.2", environmentIndex: 1,
                flagWidthsSortedByKey: [(key: "show_store", width: 0)], selections: [:]
            ) == "2026-06-17.2.146C")
        // production: show_store has two paths → 1 bit.
        #expect(
            ConfigFingerprint.encode(
                configVersion: "2026-06-17.2", environmentIndex: 2,
                flagWidthsSortedByKey: [(key: "show_store", width: 1)],
                selections: ["show_store": 0]
            ) == "2026-06-17.2.1848")
        #expect(
            ConfigFingerprint.encode(
                configVersion: "2026-06-17.2", environmentIndex: 2,
                flagWidthsSortedByKey: [(key: "show_store", width: 1)],
                selections: ["show_store": 1]
            ) == "2026-06-17.2.1A46")
    }

    // MARK: - End-to-end compute() against the same vectors

    @Test func computeReproducesDocumentedCodes() throws {
        let config = try decode(sampleJSON)

        #expect(
            ConfigFingerprint.compute(
                configuration: config, environment: .development,
                context: context(), localID: localID, customAttributeResolver: { _ in false }
            ) == "2026-06-17.2.1070")

        #expect(
            ConfigFingerprint.compute(
                configuration: config, environment: .beta,
                context: context(), localID: localID, customAttributeResolver: { _ in false }
            ) == "2026-06-17.2.146C")

        // Production, condition fails (build 1000 < 1234) → default path 0.
        #expect(
            ConfigFingerprint.compute(
                configuration: config, environment: .production,
                context: context(buildNumber: "1000"), localID: localID,
                customAttributeResolver: { _ in false }
            ) == "2026-06-17.2.1848")

        // Production, condition passes (build 2000 >= 1234) → conditional path 1.
        #expect(
            ConfigFingerprint.compute(
                configuration: config, environment: .production,
                context: context(buildNumber: "2000"), localID: localID,
                customAttributeResolver: { _ in false }
            ) == "2026-06-17.2.1A46")
    }

    // MARK: - Path resolution

    @Test func pathCountMatchesEnumeration() throws {
        let config = try decode(sampleJSON)
        let prod = FlagEvaluator(
            configuration: config, environment: .production, context: context(),
            localID: localID, customAttributeResolver: { _ in false })
        let dev = FlagEvaluator(
            configuration: config, environment: .development, context: context(),
            localID: localID, customAttributeResolver: { _ in false })
        #expect(prod.pathCount(flagKey: "show_store") == 2)  // default + conditional
        #expect(dev.pathCount(flagKey: "show_store") == 1)  // default only
    }

    @Test func resolvesRolloutPaths() throws {
        let json = """
            {
              "schema_version": 1, "config_version": "2026-06-18.1",
              "published_at": "2026-06-18T00:00:00.000Z", "app_identifier": "x",
              "flags": {
                "roll_in": { "type": "bool",
                  "development": { "default": false, "variants": [] },
                  "beta": { "default": false, "variants": [] },
                  "production": { "default": false, "variants": [
                    { "type": "rollout", "order": 1, "value": true, "rollout": "r_in" } ] } },
                "roll_out": { "type": "bool",
                  "development": { "default": false, "variants": [] },
                  "beta": { "default": false, "variants": [] },
                  "production": { "default": false, "variants": [
                    { "type": "rollout", "order": 1, "value": true, "rollout": "r_out" } ] } }
              },
              "tests": {},
              "rollouts": {
                "r_in": { "name": "r_in", "type": "rollout", "salt": "s", "conditions": [], "percentage": 100 },
                "r_out": { "name": "r_out", "type": "rollout", "salt": "s", "conditions": [], "percentage": 0 }
              }
            }
            """
        let config = try decode(json)
        let eval = FlagEvaluator(
            configuration: config, environment: .production, context: context(),
            localID: localID, customAttributeResolver: { _ in false })
        #expect(eval.resolvePathIndex(flagKey: "roll_in") == 1)  // enrolled → rollout path
        #expect(eval.resolvePathIndex(flagKey: "roll_out") == 0)  // not enrolled → default
    }

    @Test func resolvesTestGroupPaths() throws {
        // control 0% / treatment 100% → every client lands in treatment (group index 1).
        let json = """
            {
              "schema_version": 1, "config_version": "2026-06-18.2",
              "published_at": "2026-06-18T00:00:00.000Z", "app_identifier": "x",
              "flags": {
                "paywall_copy": { "type": "string",
                  "development": { "default": "control", "variants": [] },
                  "beta": { "default": "control", "variants": [] },
                  "production": { "default": "control", "variants": [
                    { "type": "test", "order": 1, "test": "t",
                      "values": { "control": "control", "treatment": "shiny" } } ] } }
              },
              "tests": {
                "t": { "name": "t", "type": "test", "salt": "s", "conditions": [],
                  "groups": [ { "name": "control", "percentage": 0 },
                              { "name": "treatment", "percentage": 100 } ] }
              },
              "rollouts": {}
            }
            """
        let config = try decode(json)
        let eval = FlagEvaluator(
            configuration: config, environment: .production, context: context(),
            localID: localID, customAttributeResolver: { _ in false })
        // paths: [default, control, treatment] → treatment is index 2.
        #expect(eval.pathCount(flagKey: "paywall_copy") == 3)
        #expect(eval.resolvePathIndex(flagKey: "paywall_copy") == 2)
    }
}
