import Foundation

/// Errors thrown by ``JWSVerifier``.
///
/// Granular cases let command-line tooling explain *why* verification failed;
/// the SDK collapses all of them into `BuntingError.signatureVerificationFailed`.
public enum JWSVerificationError: Error, Sendable, Equatable {
    /// The JWS is not a well-formed detached compact serialization
    /// (`header..signature`), or a segment failed to decode.
    case malformedJWS
    /// The header's `alg` is missing or not `"RS256"`. `nil` means missing.
    case unsupportedAlgorithm(String?)
    /// The header's `b64` is missing or not `false` (RFC 7797 requires the
    /// detached payload to be unencoded).
    case invalidB64Parameter
    /// The header's `crit` is missing, empty, or names an extension other
    /// than `"b64"` — RFC 7515 §4.1.11 requires rejecting a JWS whose `crit`
    /// contains an extension the verifier does not understand.
    case unsupportedCriticalParameters
    /// The JWS header names a `kid` that is not in the provided key set.
    case unknownKid(String)
    /// A public key PEM could not be parsed into an RSA key.
    case invalidPublicKey
    /// The signature does not verify over the given payload bytes.
    case signatureMismatch
}

extension JWSVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedJWS:
            return "Malformed detached JWS (expected compact form header..signature)"
        case .unsupportedAlgorithm(let alg):
            if let alg {
                return "Unsupported JWS alg: \(alg) (expected RS256)"
            }
            return "JWS header is missing the required alg parameter"
        case .invalidB64Parameter:
            return "JWS header must set b64: false (RFC 7797 detached payload)"
        case .unsupportedCriticalParameters:
            return "JWS header crit must be exactly [\"b64\"]"
        case .unknownKid(let kid):
            return "No public key found for kid: \(kid)"
        case .invalidPublicKey:
            return "Public key PEM could not be parsed as an RSA key"
        case .signatureMismatch:
            return "Signature does not match the payload bytes"
        }
    }
}
