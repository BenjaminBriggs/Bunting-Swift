import Foundation
import Security

/// Verifies a detached JWS (RFC 7797, unencoded payload) over the exact config
/// bytes. The signing input is `BASE64URL(protectedHeader) + "." + <config bytes>`,
/// and the compact detached form is `<protectedHeader>..<signature>`.
///
/// This binds the signature to the precise bytes that were fetched — a tampered
/// config fails verification.
enum JWSVerifier {

    static func verifyDetached(jws: String, payload: Data, publicKeys: [PublicKeyInfo]) throws {
        // Keep empty segments: detached compact form is `header..signature`.
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            throw BuntingError.signatureVerificationFailed
        }
        let protectedSegment = parts[0]

        guard
            let headerData = base64URLDecode(protectedSegment),
            let headerJSON = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
            let kid = headerJSON["kid"] as? String
        else {
            throw BuntingError.signatureVerificationFailed
        }

        guard let keyInfo = publicKeys.first(where: { $0.kid == kid }) else {
            throw BuntingError.signatureVerificationFailed
        }
        let publicKey = try convertPEMToSecKey(keyInfo.pem)

        // Signing input binds to the EXACT fetched payload bytes.
        var signingInput = Data(protectedSegment.utf8)
        signingInput.append(0x2E) // "."
        signingInput.append(payload)

        guard let signature = base64URLDecode(parts[2]) else {
            throw BuntingError.signatureVerificationFailed
        }

        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            &error
        )
        if verified == false {
            throw BuntingError.signatureVerificationFailed
        }
    }

    // MARK: - Helpers

    /// Decode base64url (RFC 4648 §5), tolerating missing padding.
    static func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: s)
    }

    static func convertPEMToSecKey(_ pem: String) throws -> SecKey {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let der = Data(base64Encoded: base64) else {
            throw BuntingError.signatureVerificationFailed
        }

        // SecKeyCreateWithData wants a PKCS#1 RSAPublicKey; admin emits SPKI
        // ("BEGIN PUBLIC KEY"), so unwrap the SPKI envelope if present.
        let pkcs1 = pkcs1FromSPKI(der)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error)
        else {
            throw BuntingError.signatureVerificationFailed
        }
        return secKey
    }

    /// Extract the PKCS#1 RSAPublicKey from a SubjectPublicKeyInfo DER.
    /// Returns the input unchanged if it is not SPKI (e.g. already PKCS#1).
    /// SPKI = SEQUENCE { SEQUENCE (AlgorithmIdentifier), BIT STRING (key) }.
    private static func pkcs1FromSPKI(_ der: Data) -> Data {
        let bytes = [UInt8](der)
        var i = 0

        func readTLV() -> (tag: UInt8, contentStart: Int, length: Int)? {
            guard i < bytes.count else { return nil }
            let tag = bytes[i]; i += 1
            guard i < bytes.count else { return nil }
            var len = Int(bytes[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7f
                guard n > 0, n <= 4, i + n <= bytes.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(bytes[i]); i += 1 }
            }
            return (tag, i, len)
        }

        guard let outer = readTLV(), outer.tag == 0x30 else { return der }       // SPKI SEQUENCE
        guard let algId = readTLV(), algId.tag == 0x30 else { return der }       // AlgorithmIdentifier
        i = algId.contentStart + algId.length                                    // skip algId content
        guard let bitString = readTLV(), bitString.tag == 0x03 else { return der } // BIT STRING

        // First content byte of a BIT STRING is the "unused bits" count (0x00 here).
        let start = bitString.contentStart + 1
        let end = bitString.contentStart + bitString.length
        guard start < end, end <= bytes.count else { return der }
        return Data(bytes[start..<end])
    }
}
