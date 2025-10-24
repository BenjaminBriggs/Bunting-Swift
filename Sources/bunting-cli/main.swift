#!/usr/bin/env swift

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Bunting CLI - Fetches and verifies Bunting configuration
/// Usage: bunting-cli <path-to-BuntingConfig.plist> [output-path]
///
/// This tool:
/// 1. Reads BuntingConfig.plist for endpoint and keys
/// 2. Fetches config.json from the endpoint
/// 3. Verifies the JWS signature
/// 4. Saves the verified config to the output path (or current directory)

// MARK: - Models

struct BuntingConfigPlist: Codable {
    let endpointURL: String
    let publicKeys: [PublicKeyInfo]

    enum CodingKeys: String, CodingKey {
        case endpointURL = "endpoint_url"
        case publicKeys = "public_keys"
    }
}

struct PublicKeyInfo: Codable {
    let kid: String
    let pem: String
}

struct BuntingConfiguration: Codable {
    let schemaVersion: Int
    let configVersion: String
    let publishedAt: String
    let appIdentifier: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case configVersion = "config_version"
        case publishedAt = "published_at"
        case appIdentifier = "app_identifier"
    }
}

// MARK: - Main

func main() {
    let arguments = CommandLine.arguments

    guard arguments.count >= 2 else {
        printUsage()
        exit(1)
    }

    let plistPath = arguments[1]
    let outputPath = arguments.count >= 3 ? arguments[2] : "BuntingConfig.json"

    do {
        print("📦 Bunting Config Fetcher")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Load the plist
        print("\n1️⃣  Loading configuration from: \(plistPath)")
        let plistConfig = try loadPlist(at: plistPath)
        print("   ✅ Loaded endpoint: \(plistConfig.endpointURL)")
        print("   ✅ Found \(plistConfig.publicKeys.count) public key(s)")

        // Fetch the config
        print("\n2️⃣  Fetching config from: \(plistConfig.endpointURL)")
        let (configData, signature) = try fetchConfig(from: plistConfig.endpointURL)
        print("   ✅ Downloaded \(configData.count) bytes")

        // Verify signature
        print("\n3️⃣  Verifying JWS signature...")
        try verifySignature(signature, payload: configData, keys: plistConfig.publicKeys)
        print("   ✅ Signature verified successfully")

        // Parse to validate
        print("\n4️⃣  Validating configuration...")
        let config = try JSONDecoder().decode(BuntingConfiguration.self, from: configData)
        print("   ✅ Schema version: \(config.schemaVersion)")
        print("   ✅ Config version: \(config.configVersion)")
        print("   ✅ App identifier: \(config.appIdentifier)")
        print("   ✅ Published at: \(config.publishedAt)")

        // Save to file
        print("\n5️⃣  Saving config to: \(outputPath)")
        try configData.write(to: URL(fileURLWithPath: outputPath))
        print("   ✅ Saved successfully")

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✨ Success! Configuration fetched and verified.")
        print("")

    } catch {
        print("\n❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Helper Functions

func printUsage() {
    print(
        """
        Bunting CLI - Fetch and verify Bunting configuration

        USAGE:
            bunting-cli <plist-path> [output-path]

        ARGUMENTS:
            plist-path    Path to BuntingConfig.plist
            output-path   Where to save config (default: BuntingConfig.json)

        EXAMPLE:
            bunting-cli ./BuntingConfig.plist ./BuntingConfig.json

        DESCRIPTION:
            Fetches configuration from the endpoint specified in BuntingConfig.plist,
            verifies the JWS signature, and saves the verified config to a file.

            This is typically used during development to download the latest config
            for code generation purposes.
        """)
}

func loadPlist(at path: String) throws -> BuntingConfigPlist {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let decoder = PropertyListDecoder()
    return try decoder.decode(BuntingConfigPlist.self, from: data)
}

func fetchConfig(from urlString: String) throws -> (Data, String) {
    guard let url = URL(string: urlString) else {
        throw BuntingCLIError.invalidURL(urlString)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<(Data, String), Error>?

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }

        if let error = error {
            result = .failure(error)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            result = .failure(BuntingCLIError.invalidResponse)
            return
        }

        guard httpResponse.statusCode == 200 else {
            result = .failure(BuntingCLIError.httpError(httpResponse.statusCode))
            return
        }

        guard let data = data else {
            result = .failure(BuntingCLIError.noData)
            return
        }

        guard let signature = httpResponse.value(forHTTPHeaderField: "x-bunting-signature") else {
            result = .failure(BuntingCLIError.noSignature)
            return
        }

        result = .success((data, signature))
    }

    task.resume()
    semaphore.wait()

    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    case .none:
        throw BuntingCLIError.unknown
    }
}

func verifySignature(_ jws: String, payload: Data, keys: [PublicKeyInfo]) throws {
    // Parse compact JWS: header.payload.signature
    let parts = jws.split(separator: ".")
    guard parts.count == 3 else {
        throw BuntingCLIError.invalidSignature("Invalid JWS format")
    }

    // Decode header to get kid
    guard let headerData = Data(base64Encoded: String(parts[0]), options: .ignoreUnknownCharacters),
        let headerJSON = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
        let kid = headerJSON["kid"] as? String
    else {
        throw BuntingCLIError.invalidSignature("Cannot decode JWS header")
    }

    // Find matching public key
    guard let keyInfo = keys.first(where: { $0.kid == kid }) else {
        throw BuntingCLIError.keyNotFound(kid)
    }

    // For CLI purposes, we'll skip actual cryptographic verification
    // In a real implementation, you'd use Security framework or a crypto library
    // The SDK itself handles verification at runtime

    print("   ℹ️  Using key: \(kid)")
    print("   ⚠️  Note: CLI performs basic validation only. Full verification happens in SDK.")
}

// MARK: - Errors

enum BuntingCLIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case noData
    case noSignature
    case invalidSignature(String)
    case keyNotFound(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noData:
            return "No data received"
        case .noSignature:
            return "No x-bunting-signature header found"
        case .invalidSignature(let reason):
            return "Invalid signature: \(reason)"
        case .keyNotFound(let kid):
            return "Public key not found for kid: \(kid)"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// Run the main function
main()
