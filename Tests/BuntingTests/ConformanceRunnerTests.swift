import Foundation
import Testing

@testable import Bunting
@testable import BuntingVerify

/// Iterates the vendored conformance bundle produced by the admin's real
/// implementations. Passing this suite defines a correct Bunting client and is
/// the completion gate for the two-axis contract phase.
@Suite("Conformance")
struct ConformanceRunnerTests {

    private func load(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Conformance"))
        return try Data(contentsOf: url)
    }

    // MARK: Bucketing

    struct BucketingSet: Decodable {
        let cases: [Case]
        struct Case: Decodable {
            let salt: String
            let identifier: String
            let bucket: Int
            let swiftApplicable: Bool?
            enum CodingKeys: String, CodingKey {
                case salt, identifier, bucket, swiftApplicable = "swift_applicable"
            }
        }
    }

    @Test func bucketingVectors() throws {
        let set = try JSONDecoder().decode(BucketingSet.self, from: load("bucketing"))
        // Per the bundle contract, run every case not explicitly flagged
        // swift_applicable:false. Those are canonical UUID identifiers the SDK can
        // reproduce; the flagged-out cases use non-UUID strings that only the
        // admin's string-hashing reference exercises.
        let applicable = set.cases.filter { $0.swiftApplicable != false }
        #expect(applicable.count >= 100)
        for c in applicable {
            let uuid = try #require(
                UUID(uuidString: c.identifier),
                "swift_applicable case must use a canonical UUID identifier: \(c.identifier)")
            #expect(Bucketing.bucket(salt: c.salt, localID: uuid) == c.bucket)
        }
    }

    // MARK: Evaluation

    struct EvaluationSet: Decodable { let artifact: BuntingConfiguration; let cases: [Case]
        struct Case: Decodable {
            let context: VectorContext
            let flagKey: String
            let environment: String
            let expectedValue: FlagValue
            let expectedSource: String
            enum CodingKeys: String, CodingKey {
                case context, flagKey = "flag_key", environment
                case expectedValue = "expected_value", expectedSource = "expected_source"
            }
        }
    }
    struct VectorContext: Decodable {
        let platform: String; let deviceClass: String?; let osVersion: String
        let appVersion: String; let buildNumber: String; let deviceModel: String
        let region: String?; let language: String
        let reservedAttributes: [String: String]?; let localID: String
        enum CodingKeys: String, CodingKey {
            case platform, deviceClass = "device_class", osVersion = "os_version"
            case appVersion = "app_version", buildNumber = "build_number"
            case deviceModel = "device_model", region, language
            case reservedAttributes = "reserved_attributes", localID = "local_id"
        }
    }

    /// Shared context builder used by the evaluation and fingerprint sets.
    private func makeContext(_ vc: VectorContext) -> EvaluationContext {
        EvaluationContext(
            platform: vc.platform, osVersion: vc.osVersion,
            appVersion: vc.appVersion, buildNumber: vc.buildNumber,
            deviceModel: vc.deviceModel, region: vc.region,
            language: vc.language, deviceClass: vc.deviceClass,
            reservedAttributes: vc.reservedAttributes ?? [:])
    }

    @Test func evaluationVectors() throws {
        let set = try JSONDecoder().decode(EvaluationSet.self, from: load("evaluation"))
        #expect(set.cases.isEmpty == false)
        for c in set.cases {
            let env = try #require(BuntingEnvironment(rawValue: c.environment))
            let localID = try #require(UUID(uuidString: c.context.localID))
            let evaluator = FlagEvaluator(
                configuration: set.artifact, environment: env,
                context: makeContext(c.context), localID: localID,
                customAttributeResolver: { _ in false })
            let actual = try #require(
                evaluator.evaluate(flagKey: c.flagKey),
                "no value for flag \(c.flagKey)")
            #expect(actual == c.expectedValue,
                "flag \(c.flagKey) [\(c.environment)] expected \(c.expectedValue), got \(actual)")
        }
    }

    // MARK: Fingerprint (encode direction — the SDK has no fingerprint decoder, so
    // the bundle's `decode_cases` are exercised by decoder-bearing implementers only).

    struct FingerprintSet: Decodable {
        let artifact: BuntingConfiguration
        let cases: [Case]
        struct Case: Decodable {
            let context: VectorContext
            let environment: String
            let code: String
        }
    }

    @Test func fingerprintVectors() throws {
        let set = try JSONDecoder().decode(FingerprintSet.self, from: load("fingerprint"))
        #expect(set.cases.isEmpty == false)
        for c in set.cases {
            let env = try #require(BuntingEnvironment(rawValue: c.environment))
            let localID = try #require(UUID(uuidString: c.context.localID))
            let code = ConfigFingerprint.compute(
                configuration: set.artifact, environment: env,
                context: makeContext(c.context), localID: localID,
                customAttributeResolver: { _ in false })
            #expect(code == c.code, "fingerprint [\(c.environment)] expected \(c.code), got \(code)")
        }
    }

    // MARK: Signature

    struct SignatureSet: Decodable {
        let cases: [Case]
        struct Case: Decodable {
            let kind: String
            let configB64: String
            let jws: String
            let verifyKid: String
            let verifyPem: String
            let expectValid: Bool
            enum CodingKeys: String, CodingKey {
                case kind, configB64 = "config_b64", jws
                case verifyKid = "verify_kid", verifyPem = "verify_pem"
                case expectValid = "expect_valid"
            }
        }
    }

    @Test func signatureVectors() throws {
        let set = try JSONDecoder().decode(SignatureSet.self, from: load("signature"))
        #expect(set.cases.isEmpty == false)
        for c in set.cases {
            let payload = try #require(Data(base64Encoded: c.configB64))
            var didThrow = false
            do {
                try JWSVerifier.verifyDetached(
                    jws: c.jws, payload: payload,
                    publicKeys: [PublicKeyInfo(kid: c.verifyKid, pem: c.verifyPem)])
            } catch {
                didThrow = true
            }
            // valid cases must verify (no throw); every other kind must be rejected.
            #expect(didThrow == (c.expectValid == false), "signature \(c.kind)")
        }
    }

    // MARK: Bootstrap (contract-level: required fields present + endpoint ends in config.json)

    @Test func bootstrapVectors() throws {
        let root = try #require(
            try JSONSerialization.jsonObject(with: load("bootstrap")) as? [String: Any])
        let cases = try #require(root["cases"] as? [[String: Any]])
        #expect(cases.isEmpty == false)
        for c in cases {
            let expectedValid = (c["valid"] as? Bool) ?? false
            let document = (c["document"] as? [String: Any]) ?? [:]
            let hasIdentifier = (document["app_identifier"] as? String) != nil
            let endpoint = document["endpoint_url"] as? String
            let isValid = hasIdentifier && (endpoint?.hasSuffix("config.json") ?? false)
            #expect(isValid == expectedValid, "bootstrap \(c["name"] ?? "")")
        }
    }
}
