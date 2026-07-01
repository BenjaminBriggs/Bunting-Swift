import BuntingVerify
import XCTest

@testable import Bunting

/// Cross-language interop: the fixture below was produced by the bunting-admin
/// publish path (Node + jose) — an SPKI RSA-2048 public key and a detached JWS
/// (RFC 7797) over the exact `config` bytes. These tests prove the Swift SDK
/// verifies real admin output and rejects tampering.
final class SignatureVerificationTests: XCTestCase {

    // base64 of the exact config.json bytes that were signed.
    private let configB64 =
        "ewogICJzY2hlbWFfdmVyc2lvbiI6IDEsCiAgImNvbmZpZ192ZXJzaW9uIjogIjIwMjYtMDYtMTYuMSIsCiAgImZsYWdzIjoge30KfQ=="

    // base64 of the SPKI public-key PEM ("-----BEGIN PUBLIC KEY-----").
    private let pemB64 =
        "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFwc0hwWFZUZ0ZxSkpKcmQxUlZaawoxTGFtZnRhelFKQTFMZUlYUWxqNlhoVVBTanhVdGxlQlZEdlQzVUxBUy9sejBNTHFMY0VCa3dSUk1pUGdKQmV4CjhVSE16bllPMkxVeVNzZUpHeVBVK0p1N2k2dXVGcjdvUXlxdGNxMlVrVnM2OHloOUpDZlc1U3V3SWhRUktGOHIKbFczWHR5c2g4TnBSTE1IUUozcmhobTRnOG92ZnRIWEl5TlZzSXJEeGN3VjJMbDE0OEk0ZkZENmZzWWZwcFNsZwo3d09TTFAxaFA5S1NMdS80TWZERFBqRXI2VEFxUGJRdVZlNWhjMjkrR2MvcDBuRWl2ZjB5U0hzeGlUeFVvOUIrCmRmSGVZYVZEdVIxK1dlWjF0bXVmblBrR1l4eXZjQnNvYjF1YmNmbXlxOXRienFGUWgvS2RqQlRIc0NyM2ttdnMKelFJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="

    private let jws =
        "eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUta2V5IiwiYjY0IjpmYWxzZSwiY3JpdCI6WyJiNjQiXX0..DvmtxFFGiIRYXZj1kzUV-RqpejHm2XryADQzdMI-0fqdmEOPXCDH4AquknePi6nr-9hmfl6NzPHfbk3J9KIV_oJwTxCTJB8YoaDtDpttBdOwXFL4auxeixs2p-FGwC5UaOq_DG7FilFelIctdrYDkV7QWbm_SzHUBKHveI9nhlwLNvbBj_AFp6nPTOHTaDS2ZliwVLIJyvmponufFzPZOfAvzybWk7vH0vR7M28xnpD_NcCp1BvFTo2eANdsHZc7_gm74L-Dx--DHe_bjSEGKiqcezvfY9hUBM9lc4HqkQMQEvXoaxvvMq3xfolTr3MI6CzsvCfOxaFSiYDtoXVF0Q"

    private var config: Data { Data(base64Encoded: configB64)! }
    private var keys: [PublicKeyInfo] {
        [PublicKeyInfo(kid: "fixture-key", pem: String(data: Data(base64Encoded: pemB64)!, encoding: .utf8)!)]
    }

    /// Builds a detached JWS with a custom protected header, reusing the
    /// fixture's real signature segment. Header validation must reject
    /// before the (now header-mismatched) signature is ever verified, so
    /// these fixtures don't need a valid signature to test rejection.
    private func jwsWithHeader(_ header: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let headerB64 = base64URLEncode(headerData)
        let signatureSegment = jws.split(separator: ".", omittingEmptySubsequences: false)[2]
        return "\(headerB64)..\(signatureSegment)"
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testVerifiesRealAdminDetachedSignature() throws {
        XCTAssertNoThrow(
            try JWSVerifier.verifyDetached(jws: jws, payload: config, publicKeys: keys)
        )
    }

    func testRejectsTamperedConfigBytes() {
        var tampered = config
        tampered.append(0x20)  // one extra byte
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jws, payload: tampered, publicKeys: keys)
        )
    }

    func testRejectsUnknownKid() {
        let wrongKeys = [PublicKeyInfo(kid: "some-other-kid", pem: keys[0].pem)]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jws, payload: config, publicKeys: wrongKeys)
        )
    }

    /// A different RSA-2048 public key registered under the fixture's kid must
    /// fail — proves the actual cryptographic check gates, not just kid lookup.
    func testRejectsWrongKeyWithValidKid() {
        let otherPemB64 =
            "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFwbjRvS3c0aWkzNlRyb3U1Vm01cwpMQTFQZWpYL1YvRVBaaFN1dFp5RS92TmlJaWZMVmViR3Rjb1JXVXBrdkQ2ZnprOTc1dWNWY1VmTjArVkNxSjdlCnVhTHduNStBLzdhbmp5c2ljaEVCZzd5WUtSKzIvVXlycHd4b0VoY1ZQbEkrNlhrcmNsNXZYOEhIRkZtVzJQY0EKWVhDaThKUWgwYldaeHdudmhVb3g2MlNhYWR4OTZlUjl3OUUycnJWYUY4WWxCMWlCaXFTZnJYcjRuZ1A1WXA2VApDejBWa3FpaXgyNkg0eThDZlhQRU5hVjgyWkduUmxZYVI1d2p5NGUxUlJYYlBjVytHanNuSUdtcDJtZnNNSHMvClVCb0JhbkRsMDZCRjdycTFMN3JiaGFDeUo3c21TZ0F2VVdGMy9EdWpjZ1V6RHZ0MXVLanBMR3FDVFpoSHE4VUsKalFJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="
        let wrongKey = PublicKeyInfo(
            kid: "fixture-key",
            pem: String(data: Data(base64Encoded: otherPemB64)!, encoding: .utf8)!
        )
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jws, payload: config, publicKeys: [wrongKey])
        )
    }

    /// Detached compact form with the signature segment stripped must be rejected.
    func testRejectsStrippedSignature() {
        let protectedSegment = jws.split(separator: ".", omittingEmptySubsequences: false)[0]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(
                jws: "\(protectedSegment)..", payload: config, publicKeys: keys)
        )
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: "", payload: config, publicKeys: keys)
        )
    }

    /// A two-segment string (attached-style parse of a detached JWS) is malformed.
    func testRejectsTwoPartJWS() {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false)
        let twoPart = "\(parts[0]).\(parts[2])"
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: twoPart, payload: config, publicKeys: keys)
        )
    }

    // MARK: - Header strictness (alg / b64 / crit)

    func testRejectsUnsupportedAlgorithm() {
        let header: [String: Any] = ["alg": "RS512", "kid": "fixture-key", "b64": false, "crit": ["b64"]]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jwsWithHeader(header), payload: config, publicKeys: keys)
        ) { error in
            guard case JWSVerificationError.unsupportedAlgorithm(let alg) = error else {
                return XCTFail("Expected unsupportedAlgorithm, got \(error)")
            }
            XCTAssertEqual(alg, "RS512")
        }
    }

    func testRejectsNoneAlgorithm() {
        let header: [String: Any] = ["alg": "none", "kid": "fixture-key", "b64": false, "crit": ["b64"]]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jwsWithHeader(header), payload: config, publicKeys: keys)
        ) { error in
            guard case JWSVerificationError.unsupportedAlgorithm(let alg) = error else {
                return XCTFail("Expected unsupportedAlgorithm, got \(error)")
            }
            XCTAssertEqual(alg, "none")
        }
    }

    func testRejectsMissingB64() {
        let header: [String: Any] = ["alg": "RS256", "kid": "fixture-key", "crit": ["b64"]]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jwsWithHeader(header), payload: config, publicKeys: keys)
        ) { error in
            XCTAssertEqual(error as? JWSVerificationError, .invalidB64Parameter)
        }
    }

    func testRejectsMissingCrit() {
        let header: [String: Any] = ["alg": "RS256", "kid": "fixture-key", "b64": false]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jwsWithHeader(header), payload: config, publicKeys: keys)
        ) { error in
            XCTAssertEqual(error as? JWSVerificationError, .unsupportedCriticalParameters)
        }
    }

    func testRejectsUnknownCriticalExtension() {
        let header: [String: Any] = [
            "alg": "RS256", "kid": "fixture-key", "b64": false, "crit": ["b64", "exp"],
        ]
        XCTAssertThrowsError(
            try JWSVerifier.verifyDetached(jws: jwsWithHeader(header), payload: config, publicKeys: keys)
        ) { error in
            XCTAssertEqual(error as? JWSVerificationError, .unsupportedCriticalParameters)
        }
    }
}
