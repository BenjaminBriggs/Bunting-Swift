import Foundation
import Security

/// Generates an ephemeral RSA-2048 key pair and produces detached JWS
/// signatures (RFC 7797, unencoded payload) matching exactly what
/// `BuntingVerify.JWSVerifier.verifyDetached` expects: compact form
/// `<protectedHeader>..<signature>`, RS256, `b64: false`, `crit: ["b64"]`.
///
/// Exists purely to build self-contained, end-to-end-valid fixtures for
/// bunting-cli subprocess tests, without depending on BuntingVerify's
/// internal (non-public) PEM/base64url helpers.
struct RSATestSigner {
    let kid: String
    private let privateKey: SecKey
    let publicKeyPEM: String

    init(kid: String) throws {
        self.kid = kid

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw RSATestSigningError.publicKeyDerivationFailed
        }
        guard
            let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw error!.takeRetainedValue() as Error
        }

        self.privateKey = privateKey
        // SecKeyCopyExternalRepresentation for RSA yields PKCS#1 DER.
        // JWSVerifier's PEM parser falls back to treating non-SPKI DER as
        // already-PKCS1, so wrapping it in "BEGIN PUBLIC KEY" markers works.
        let base64 = publicKeyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        self.publicKeyPEM = "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----\n"
    }

    /// Produces a compact detached JWS over `payload`.
    func detachedJWS(over payload: Data) throws -> String {
        let header: [String: Any] = ["alg": "RS256", "kid": kid, "b64": false, "crit": ["b64"]]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let headerB64 = Self.base64URLEncode(headerData)

        var signingInput = Data(headerB64.utf8)
        signingInput.append(0x2E)  // "."
        signingInput.append(payload)

        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateKey, .rsaSignatureMessagePKCS1v15SHA256, signingInput as CFData, &error)
                as Data?
        else {
            throw error!.takeRetainedValue() as Error
        }

        return "\(headerB64)..\(Self.base64URLEncode(signature))"
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum RSATestSigningError: Error {
    case publicKeyDerivationFailed
}
