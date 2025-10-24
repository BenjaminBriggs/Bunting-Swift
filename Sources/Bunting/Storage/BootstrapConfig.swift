import Foundation

/// Bootstrap configuration loaded from BuntingConfig.plist
struct BootstrapConfig: Codable {
    let endpointURL: String
    let publicKeys: [PublicKeyInfo]
    let fetchPolicy: FetchPolicy
    let certPins: [String]?

    enum CodingKeys: String, CodingKey {
        case endpointURL = "endpoint_url"
        case publicKeys = "public_keys"
        case fetchPolicy = "fetch_policy"
        case certPins = "cert_pins"
    }

    /// Loads bootstrap configuration from the main bundle
    static func load() throws -> BootstrapConfig {
        guard let url = Bundle.main.url(forResource: "BuntingConfig", withExtension: "plist") else {
            throw BuntingError.invalidConfiguration
        }

        let data = try Data(contentsOf: url)
        let decoder = PropertyListDecoder()
        return try decoder.decode(BootstrapConfig.self, from: data)
    }
}

/// Public key information for JWS verification
struct PublicKeyInfo: Codable {
    let kid: String
    let pem: String
}

/// Fetch policy configuration
struct FetchPolicy: Codable {
    let minIntervalSeconds: Int
    let hardTTLDays: Int

    enum CodingKeys: String, CodingKey {
        case minIntervalSeconds = "min_interval_seconds"
        case hardTTLDays = "hard_ttl_days"
    }
}
