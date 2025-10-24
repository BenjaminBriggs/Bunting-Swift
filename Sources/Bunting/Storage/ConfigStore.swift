import CryptoKit
import Foundation

/// Manages configuration fetching, verification, and caching
actor ConfigStore {
    private let bootstrapConfig: BootstrapConfig
    private let fileManager = FileManager.default

    private var activeConfig: BuntingConfiguration?
    private var lastFetchTime: Date?
    private var cachedETag: String?
    private var cachedLastModified: String?
    private var lastTTLRefresh: Date?

    private let cacheDirectory: URL
    private let configFileName = "config_v1.json"
    private let metadataFileName = "metadata.json"

    // Delegate for event notifications
    private weak var eventsDelegate: BuntingEventsDelegate?

    /// Update the events delegate
    func setEventsDelegate(_ delegate: BuntingEventsDelegate?) {
        self.eventsDelegate = delegate
    }

    init(bootstrapConfig: BootstrapConfig, eventsDelegate: BuntingEventsDelegate? = nil) throws {
        self.eventsDelegate = eventsDelegate
        self.bootstrapConfig = bootstrapConfig

        // Set up cache directory in Application Support
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        self.cacheDirectory = appSupport.appendingPathComponent("Bunting", isDirectory: true)

        // Create Bunting directory if needed
        if fileManager.fileExists(atPath: cacheDirectory.path) == false {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// Loads cached config if available (should be called after init)
    /// Falls back to bundled seed if no cache exists
    func loadCachedConfigIfNeeded() {
        guard activeConfig == nil else { return }

        // Try loading from cache first
        if (try? loadCachedConfig()) != nil {
            return
        }

        // Fallback to bundled seed
        try? loadBundledSeed()
    }

    // MARK: - Public API

    /// Returns the active configuration, or nil if not loaded
    func getConfiguration() -> BuntingConfiguration? {
        return activeConfig
    }

    /// Refreshes the configuration from the remote endpoint
    func refresh() async throws {
        // Check rate limiting
        if let lastFetch = lastFetchTime {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < Double(bootstrapConfig.fetchPolicy.minIntervalSeconds) {
                return  // Too soon, skip fetch
            }
        }

        // Check hard TTL
        let shouldForceRefresh: Bool
        if let lastTTL = lastTTLRefresh {
            let daysSince =
                Calendar.current.dateComponents([.day], from: lastTTL, to: Date()).day ?? 0
            shouldForceRefresh = daysSince >= bootstrapConfig.fetchPolicy.hardTTLDays
        } else {
            shouldForceRefresh = true
        }

        // Perform fetch
        try await performFetch(forceRefresh: shouldForceRefresh)
    }

    // MARK: - Fetching

    private func performFetch(forceRefresh: Bool) async throws {
        guard let url = URL(string: bootstrapConfig.endpointURL) else {
            throw BuntingError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Add conditional GET headers if we have them and not forcing refresh
        if forceRefresh == false {
            if let etag = cachedETag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = cachedLastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)

        // Notify delegate that fetch is starting
        await notifyDidStartFetch(url: url)

        let (data, response) = try await session.data(for: request)
        lastFetchTime = Date()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BuntingError.networkError(URLError(.badServerResponse))
        }

        // Handle 304 Not Modified
        if httpResponse.statusCode == 304 {
            // Config hasn't changed, update TTL and continue
            if forceRefresh {
                lastTTLRefresh = Date()
                try saveMetadata()
            }
            return
        }

        guard httpResponse.statusCode == 200 else {
            throw BuntingError.networkError(URLError(.badServerResponse))
        }

        // Extract signature from header
        guard let signatureHeader = httpResponse.value(forHTTPHeaderField: "x-bunting-signature")
        else {
            throw BuntingError.signatureVerificationFailed
        }

        // Verify JWS signature
        do {
            try verifySignature(signatureHeader, payload: data)
            await notifyDidVerifySignature(success: true)
        } catch {
            await notifyDidVerifySignature(success: false)
            await notifyDidCompleteFetch(success: false, error: error)
            throw error
        }

        // Parse configuration
        let decoder = JSONDecoder()
        let newConfig = try decoder.decode(BuntingConfiguration.self, from: data)

        // Save to cache
        try saveToCache(data, response: httpResponse)

        // Update active config
        activeConfig = newConfig
        lastTTLRefresh = Date()

        // Update cached headers
        cachedETag = httpResponse.value(forHTTPHeaderField: "ETag")
        cachedLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        try saveMetadata()

        // Notify successful fetch completion
        await notifyDidCompleteFetch(success: true, error: nil)
    }

    // MARK: - JWS Verification

    private func verifySignature(_ jws: String, payload: Data) throws {
        // Parse compact JWS: header.payload.signature
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else {
            throw BuntingError.signatureVerificationFailed
        }

        // Decode header to get kid
        guard
            let headerData = Data(
                base64Encoded: String(parts[0]), options: .ignoreUnknownCharacters),
            let headerJSON = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
            let kid = headerJSON["kid"] as? String
        else {
            throw BuntingError.signatureVerificationFailed
        }

        // Find matching public key
        guard let keyInfo = bootstrapConfig.publicKeys.first(where: { $0.kid == kid }) else {
            throw BuntingError.signatureVerificationFailed
        }

        // Convert PEM to SecKey
        guard let publicKey = try? convertPEMToSecKey(keyInfo.pem) else {
            throw BuntingError.signatureVerificationFailed
        }

        // Verify signature
        // The signed data is header.payload (base64url encoded)
        let signedData = "\(parts[0]).\(parts[1])".data(using: .utf8)!

        guard
            let signatureData = Data(
                base64Encoded: String(parts[2]), options: .ignoreUnknownCharacters)
        else {
            throw BuntingError.signatureVerificationFailed
        }

        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        var error: Unmanaged<CFError>?

        let verified = SecKeyVerifySignature(
            publicKey,
            algorithm,
            signedData as CFData,
            signatureData as CFData,
            &error
        )

        if verified == false {
            throw BuntingError.signatureVerificationFailed
        }
    }

    private func convertPEMToSecKey(_ pem: String) throws -> SecKey {
        // Remove PEM headers/footers and whitespace
        let base64 =
            pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: base64) else {
            throw BuntingError.signatureVerificationFailed
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard
            let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error)
        else {
            throw BuntingError.signatureVerificationFailed
        }

        return secKey
    }

    // MARK: - Caching

    private func loadCachedConfig() throws {
        let configURL = cacheDirectory.appendingPathComponent(configFileName)

        guard fileManager.fileExists(atPath: configURL.path) else {
            throw BuntingError.invalidConfiguration
        }

        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        let config = try decoder.decode(BuntingConfiguration.self, from: data)
        activeConfig = config

        // Load metadata
        loadMetadata()

        // Notify delegate
        Task {
            await notifyDidLoadCachedConfig(version: config.configVersion)
        }
    }

    private func loadBundledSeed() throws {
        // Look for BuntingConfig.json in the main bundle
        guard let bundleURL = Bundle.main.url(forResource: "BuntingConfig", withExtension: "json")
        else {
            throw BuntingError.invalidConfiguration
        }

        let data = try Data(contentsOf: bundleURL)
        let decoder = JSONDecoder()
        let config = try decoder.decode(BuntingConfiguration.self, from: data)
        activeConfig = config

        // Notify delegate
        Task {
            await notifyDidLoadCachedConfig(version: config.configVersion)
        }
    }

    private func saveToCache(_ data: Data, response: HTTPURLResponse) throws {
        let configURL = cacheDirectory.appendingPathComponent(configFileName)
        try data.write(to: configURL, options: .atomic)
    }

    private func loadMetadata() {
        let metadataURL = cacheDirectory.appendingPathComponent(metadataFileName)

        guard fileManager.fileExists(atPath: metadataURL.path),
            let data = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return
        }

        cachedETag = metadata.etag
        cachedLastModified = metadata.lastModified
        lastFetchTime = metadata.lastFetchTime
        lastTTLRefresh = metadata.lastTTLRefresh
    }

    private func saveMetadata() throws {
        let metadata = CacheMetadata(
            etag: cachedETag,
            lastModified: cachedLastModified,
            lastFetchTime: lastFetchTime,
            lastTTLRefresh: lastTTLRefresh
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let metadataURL = cacheDirectory.appendingPathComponent(metadataFileName)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Delegate Notifications

    nonisolated private func notifyDidStartFetch(url: URL) async {
        await MainActor.run { [eventsDelegate] in
            eventsDelegate?.didStartFetch(url: url)
        }
    }

    nonisolated private func notifyDidCompleteFetch(success: Bool, error: Error?) async {
        await MainActor.run { [eventsDelegate] in
            eventsDelegate?.didCompleteFetch(success: success, error: error)
        }
    }

    nonisolated private func notifyDidVerifySignature(success: Bool) async {
        await MainActor.run { [eventsDelegate] in
            eventsDelegate?.didVerifySignature(success: success)
        }
    }

    nonisolated private func notifyDidLoadCachedConfig(version: String) async {
        await MainActor.run { [eventsDelegate] in
            eventsDelegate?.didLoadCachedConfig(version: version)
        }
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Codable {
    let etag: String?
    let lastModified: String?
    let lastFetchTime: Date?
    let lastTTLRefresh: Date?
}
