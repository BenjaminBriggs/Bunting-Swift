#!/usr/bin/env swift

import BuntingVerify
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
/// 3. Reads the detached JWS from the x-bunting-signature response header,
///    falling back to fetching <endpoint>.sig
/// 4. Cryptographically verifies the signature over the exact fetched bytes
/// 5. Saves the verified config to the output path (or current directory)

// MARK: - Models

struct BuntingConfigPlist: Codable {
    let endpointURL: String
    let publicKeys: [PublicKeyInfo]

    enum CodingKeys: String, CodingKey {
        case endpointURL = "endpoint_url"
        case publicKeys = "public_keys"
    }
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

// MARK: - Exit codes

enum ExitCode {
    static let usageOrPlistError: Int32 = 1
    static let networkError: Int32 = 2
    static let signatureError: Int32 = 3
    static let decodeError: Int32 = 4
}

// MARK: - Main

func main() {
    let arguments = CommandLine.arguments

    guard arguments.count >= 2 else {
        printUsage()
        exit(ExitCode.usageOrPlistError)
    }

    let plistPath = arguments[1]
    let outputPath = arguments.count >= 3 ? arguments[2] : "BuntingConfig.json"

    print("📦 Bunting Config Fetcher")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    // Load the plist
    print("\n1️⃣  Loading configuration from: \(plistPath)")
    let plistConfig: BuntingConfigPlist
    do {
        plistConfig = try loadPlist(at: plistPath)
    } catch {
        fail(error, code: ExitCode.usageOrPlistError)
    }
    print("   ✅ Loaded endpoint: \(plistConfig.endpointURL)")
    print("   ✅ Found \(plistConfig.publicKeys.count) public key(s)")

    guard let configURL = URL(string: plistConfig.endpointURL) else {
        fail(BuntingCLIError.invalidURL(plistConfig.endpointURL), code: ExitCode.usageOrPlistError)
    }

    // Fetch the config
    print("\n2️⃣  Fetching config from: \(plistConfig.endpointURL)")
    let configData: Data
    let headerSignature: String?
    do {
        (configData, headerSignature) = try fetchConfig(from: configURL)
    } catch {
        fail(error, code: ExitCode.networkError)
    }
    print("   ✅ Downloaded \(configData.count) bytes")

    // Obtain the detached JWS: header first, then the .sig file
    print("\n3️⃣  Verifying JWS signature...")
    let jws: String
    if let headerSignature {
        jws = headerSignature
        print("   ℹ️  Signature transport: \(SignatureTransport.headerName) header")
    } else {
        let sigURL = SignatureTransport.sigURL(for: configURL)
        do {
            jws = try fetchSignature(from: sigURL)
        } catch {
            print("   ❌ No \(SignatureTransport.headerName) header and fetching \(sigURL.absoluteString) failed")
            fail(error, code: ExitCode.signatureError)
        }
        print("   ℹ️  Signature transport: .sig fetch (\(sigURL.absoluteString))")
    }

    do {
        try JWSVerifier.verifyDetached(jws: jws, payload: configData, publicKeys: plistConfig.publicKeys)
    } catch {
        fail(error, code: ExitCode.signatureError)
    }
    print("   ✅ Signature verified")

    // Parse to validate
    print("\n4️⃣  Validating configuration...")
    let config: BuntingConfiguration
    do {
        config = try JSONDecoder().decode(BuntingConfiguration.self, from: configData)
    } catch {
        fail(error, code: ExitCode.decodeError)
    }
    print("   ✅ Schema version: \(config.schemaVersion)")
    print("   ✅ Config version: \(config.configVersion)")
    print("   ✅ App identifier: \(config.appIdentifier)")
    print("   ✅ Published at: \(config.publishedAt)")

    // Save to file — only ever reached with verified bytes
    print("\n5️⃣  Saving config to: \(outputPath)")
    do {
        try configData.write(to: URL(fileURLWithPath: outputPath))
    } catch {
        fail(error, code: ExitCode.usageOrPlistError)
    }
    print("   ✅ Saved successfully")

    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✨ Success! Configuration fetched and verified.")
    print("")
}

// MARK: - Helper Functions

func fail(_ error: Error, code: Int32) -> Never {
    print("\n❌ Error: \(error.localizedDescription)")
    exit(code)
}

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

        EXIT CODES:
            1   Usage, plist, or file-system error
            2   Network or HTTP error fetching config.json
            3   Signature missing (no header, no .sig) or verification failed
            4   Config JSON failed to decode

        DESCRIPTION:
            Fetches configuration from the endpoint specified in BuntingConfig.plist,
            reads the detached JWS from the x-bunting-signature response header
            (falling back to <endpoint>.sig), cryptographically verifies it over the
            exact fetched bytes, and saves the verified config to a file.

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

/// Fetches the config bytes plus the optional detached JWS from the
/// x-bunting-signature response header.
func fetchConfig(from url: URL) throws -> (Data, String?) {
    let (data, response) = try synchronousGET(url)
    guard response.statusCode == 200 else {
        throw BuntingCLIError.httpError(response.statusCode)
    }
    let signature = response.value(forHTTPHeaderField: SignatureTransport.headerName)
    return (data, signature)
}

/// Fetches the detached JWS from the sibling `.sig` object.
func fetchSignature(from url: URL) throws -> String {
    let (data, response) = try synchronousGET(url)
    guard response.statusCode == 200 else {
        throw BuntingCLIError.httpError(response.statusCode)
    }
    guard let jws = String(data: data, encoding: .utf8), jws.isEmpty == false else {
        throw BuntingCLIError.invalidSignature("Signature file is not valid UTF-8")
    }
    return jws.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func synchronousGET(_ url: URL) throws -> (Data, HTTPURLResponse) {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<(Data, HTTPURLResponse), Error>?

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

        guard let data = data else {
            result = .failure(BuntingCLIError.noData)
            return
        }

        result = .success((data, httpResponse))
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

// MARK: - Errors

enum BuntingCLIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case noData
    case invalidSignature(String)
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
        case .invalidSignature(let reason):
            return "Invalid signature: \(reason)"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// Run the main function
main()
