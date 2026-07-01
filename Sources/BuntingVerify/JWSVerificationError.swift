import Foundation

/// Errors thrown by ``JWSVerifier``.
///
/// Granular cases let command-line tooling explain *why* verification failed;
/// the SDK collapses all of them into `BuntingError.signatureVerificationFailed`.
public enum JWSVerificationError: Error, Sendable {
    /// The JWS is not a well-formed detached compact serialization
    /// (`header..signature`), or a segment failed to decode.
    case malformedJWS
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
        case .unknownKid(let kid):
            return "No public key found for kid: \(kid)"
        case .invalidPublicKey:
            return "Public key PEM could not be parsed as an RSA key"
        case .signatureMismatch:
            return "Signature does not match the payload bytes"
        }
    }
}
