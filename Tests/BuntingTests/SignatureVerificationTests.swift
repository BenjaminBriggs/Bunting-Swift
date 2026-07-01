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
}
