import Foundation

/// Public key information for JWS verification
public struct PublicKeyInfo: Codable, Sendable {
    public let kid: String
    public let pem: String

    public init(kid: String, pem: String) {
        self.kid = kid
        self.pem = pem
    }
}

/// The two supported signature delivery transports, defined once for the SDK
/// and the CLI: the `x-bunting-signature` response header on the `config.json`
/// response (preferred, saves a request), falling back to a sibling
/// `config.json.sig` object at the same path.
public enum SignatureTransport {
    /// Response header carrying the compact detached JWS on `config.json` responses.
    public static let headerName = "x-bunting-signature"

    /// Derives the detached-signature URL (`<config-url>.sig`) for a config URL.
    public static func sigURL(for configURL: URL) -> URL {
        return URL(string: configURL.absoluteString + ".sig") ?? configURL.appendingPathExtension("sig")
    }
}
