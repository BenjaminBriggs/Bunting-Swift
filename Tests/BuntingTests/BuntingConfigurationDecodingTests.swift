import Foundation
import Testing

@testable import Bunting

/// Direct coverage of `BuntingConfiguration`/`Flag`/`EnvironmentConfig`
/// decoding: legacy key acceptance, optional-field defaults, and a full
/// artifact round-trip exercising every flag type plus a test and a rollout.
@Suite("BuntingConfiguration Decoding")
struct BuntingConfigurationDecodingTests {

    // MARK: - Legacy / misspelled default-value keys (Flag.swift EnvironmentConfig)

    @Test("Legacy 'defaultValue' key is accepted in place of 'default'")
    func legacyDefaultValueKeyAccepted() throws {
        let json = Data(
            """
            { "defaultValue": true, "variants": [] }
            """.utf8)

        let config = try JSONDecoder().decode(EnvironmentConfig.self, from: json)
        #expect(config.default == .boolean(true))
        #expect(config.variants.isEmpty)
    }

    @Test("Misspelled 'defaultdefault' key is accepted")
    func misspelledDefaultdefaultAccepted() throws {
        let json = Data(
            """
            { "defaultdefault": "fallback", "variants": [] }
            """.utf8)

        let config = try JSONDecoder().decode(EnvironmentConfig.self, from: json)
        #expect(config.default == .string("fallback"))
    }

    @Test("Standard 'default' key takes precedence over legacy keys when both present")
    func standardKeyTakesPrecedenceOverLegacyKeys() throws {
        let json = Data(
            """
            { "default": "standard", "defaultValue": "legacy", "variants": [] }
            """.utf8)

        let config = try JSONDecoder().decode(EnvironmentConfig.self, from: json)
        #expect(config.default == .string("standard"))
    }

    @Test("Missing default value under any accepted key throws")
    func missingDefaultValueThrows() throws {
        let json = Data(
            """
            { "variants": [] }
            """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(EnvironmentConfig.self, from: json)
        }
    }

    // MARK: - Missing optional fields default correctly

    @Test("EnvironmentConfig with missing variants defaults to an empty array")
    func missingVariantsDefaultsToEmptyArray() throws {
        let json = Data(
            """
            { "default": 1 }
            """.utf8)

        let config = try JSONDecoder().decode(EnvironmentConfig.self, from: json)
        #expect(config.variants.isEmpty)
    }

    @Test("Flag with missing description and deprecated fields defaults correctly")
    func flagMissingOptionalFieldsDefaultsCorrectly() throws {
        let json = Data(
            """
            {
                "type": "bool",
                "development": { "default": false, "variants": [] },
                "beta": { "default": false, "variants": [] },
                "production": { "default": false, "variants": [] }
            }
            """.utf8)

        let flag = try JSONDecoder().decode(Flag.self, from: json)
        #expect(flag.description == nil)
        #expect(flag.deprecated == false)
    }

    @Test("Flag with explicit deprecated: true decodes correctly")
    func flagExplicitDeprecatedTrueDecodes() throws {
        let json = Data(
            """
            {
                "type": "bool",
                "deprecated": true,
                "development": { "default": false, "variants": [] },
                "beta": { "default": false, "variants": [] },
                "production": { "default": false, "variants": [] }
            }
            """.utf8)

        let flag = try JSONDecoder().decode(Flag.self, from: json)
        #expect(flag.deprecated == true)
    }

    // MARK: - Full artifact round-trip

    @Test("Full artifact round-trip decodes every flag type plus a test and a rollout")
    func fullArtifactRoundTrip() throws {
        let json = Data(
            """
            {
                "schema_version": 1,
                "config_version": "2026-07-01.1",
                "published_at": "2026-07-01T00:00:00Z",
                "app_identifier": "test-app",
                "flags": {
                    "feature/bool_flag": {
                        "type": "bool",
                        "description": "A boolean flag",
                        "development": { "default": false, "variants": [] },
                        "beta": { "default": false, "variants": [] },
                        "production": { "default": false, "variants": [] }
                    },
                    "feature/string_flag": {
                        "type": "string",
                        "description": null,
                        "development": { "default": "hello", "variants": [] },
                        "beta": { "default": "hello", "variants": [] },
                        "production": { "default": "hello", "variants": [] }
                    },
                    "feature/int_flag": {
                        "type": "int",
                        "development": { "default": 7, "variants": [] },
                        "beta": { "default": 7, "variants": [] },
                        "production": { "default": 7, "variants": [] }
                    },
                    "feature/double_flag": {
                        "type": "double",
                        "development": { "default": 1.5, "variants": [] },
                        "beta": { "default": 1.5, "variants": [] },
                        "production": { "default": 1.5, "variants": [] }
                    },
                    "feature/date_flag": {
                        "type": "date",
                        "development": { "default": "2026-01-01T00:00:00Z", "variants": [] },
                        "beta": { "default": "2026-01-01T00:00:00Z", "variants": [] },
                        "production": { "default": "2026-01-01T00:00:00Z", "variants": [] }
                    },
                    "feature/json_flag": {
                        "type": "json",
                        "development": { "default": "{\\"a\\":1}", "variants": [] },
                        "beta": { "default": "{\\"a\\":1}", "variants": [] },
                        "production": { "default": "{\\"a\\":1}", "variants": [] }
                    },
                    "feature/test_flag": {
                        "type": "string",
                        "development": {
                            "default": "control",
                            "variants": [
                                {
                                    "type": "test",
                                    "order": 1,
                                    "value": null,
                                    "values": { "control": "control-value", "treatment": "treatment-value" },
                                    "conditions": null,
                                    "test": "checkout_test",
                                    "rollout": null
                                }
                            ]
                        },
                        "beta": { "default": "control", "variants": [] },
                        "production": { "default": "control", "variants": [] }
                    },
                    "feature/rollout_flag": {
                        "type": "bool",
                        "development": {
                            "default": false,
                            "variants": [
                                {
                                    "type": "rollout",
                                    "order": 1,
                                    "value": true,
                                    "values": null,
                                    "conditions": null,
                                    "test": null,
                                    "rollout": "gradual_rollout"
                                }
                            ]
                        },
                        "beta": { "default": false, "variants": [] },
                        "production": { "default": false, "variants": [] }
                    }
                },
                "tests": {
                    "checkout_test": {
                        "name": "checkout_test",
                        "description": "Checkout CTA test",
                        "type": "test",
                        "salt": "checkout-salt",
                        "conditions": [],
                        "groups": [
                            { "name": "control", "percentage": 50 },
                            { "name": "treatment", "percentage": 50 }
                        ]
                    }
                },
                "rollouts": {
                    "gradual_rollout": {
                        "name": "gradual_rollout",
                        "description": "Gradual rollout of new checkout",
                        "type": "rollout",
                        "salt": "rollout-salt",
                        "conditions": [],
                        "percentage": 20
                    }
                }
            }
            """.utf8)

        let config = try JSONDecoder().decode(BuntingConfiguration.self, from: json)

        #expect(config.schemaVersion == 1)
        #expect(config.configVersion == "2026-07-01.1")
        #expect(config.appIdentifier == "test-app")
        #expect(config.flags.count == 8)

        #expect(config.flags["feature/bool_flag"]?.type == .boolean)
        #expect(config.flags["feature/bool_flag"]?.development.default == .boolean(false))

        #expect(config.flags["feature/string_flag"]?.type == .string)
        #expect(config.flags["feature/string_flag"]?.development.default == .string("hello"))

        #expect(config.flags["feature/int_flag"]?.type == .integer)
        #expect(config.flags["feature/int_flag"]?.development.default == .integer(7))

        #expect(config.flags["feature/double_flag"]?.type == .double)
        #expect(config.flags["feature/double_flag"]?.development.default == .double(1.5))

        #expect(config.flags["feature/date_flag"]?.type == .date)
        guard case .date = config.flags["feature/date_flag"]?.development.default else {
            Issue.record("Expected date_flag default to decode as .date")
            return
        }

        #expect(config.flags["feature/json_flag"]?.type == .json)
        #expect(config.flags["feature/json_flag"]?.development.default == .json("{\"a\":1}"))

        // Test-backed flag
        let testFlag = try #require(config.flags["feature/test_flag"])
        #expect(testFlag.development.variants.count == 1)
        #expect(testFlag.development.variants.first?.type == .test)
        #expect(testFlag.development.variants.first?.test == "checkout_test")

        let checkoutTest = try #require(config.tests["checkout_test"])
        #expect(checkoutTest.salt == "checkout-salt")
        #expect(checkoutTest.groups?.count == 2)
        #expect(checkoutTest.groups?.first?.name == "control")
        #expect(checkoutTest.groups?.first?.percentage == 50)

        // Rollout-backed flag
        let rolloutFlag = try #require(config.flags["feature/rollout_flag"])
        #expect(rolloutFlag.development.variants.first?.type == .rollout)
        #expect(rolloutFlag.development.variants.first?.rollout == "gradual_rollout")

        let gradualRollout = try #require(config.rollouts["gradual_rollout"])
        #expect(gradualRollout.percentage == 20)
        #expect(gradualRollout.salt == "rollout-salt")
    }
}
