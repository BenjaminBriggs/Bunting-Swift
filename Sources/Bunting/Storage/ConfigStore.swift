import BuntingVerify
import CryptoKit
import Foundation
import OSLog

/// Manages configuration fetching, verification, and caching
actor ConfigStore {
    private let bootstrapConfig: BootstrapConfig
    private let fileManager = FileManager.default
    private let sessionConfiguration: URLSessionConfiguration

    private var activeConfig: BuntingConfiguration?
    private var activeSource: ConfigSource?
    private var activeSignatureVerified = false
    private var lastFetchTime: Date?
    private var cachedETag: String?
    private var cachedLastModified: String?
    private var lastTTLRefresh: Date?

    private let cacheDirectory: URL
    private let configFileName = "config_v1.json"
    private let signatureFileName = "config_v1.json.sig"
    private let metadataFileName = "metadata.json"

    // Delegate for event notifications
    private weak var eventsDelegate: BuntingEventsDelegate?

    /// Update the events delegate
    func setEventsDelegate(_ delegate: BuntingEventsDelegate?) {
        self.eventsDelegate = delegate
    }

    init(
        bootstrapConfig: BootstrapConfig,
        eventsDelegate: BuntingEventsDelegate? = nil,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        cacheDirectoryOverride: URL? = nil
    ) throws {
        self.eventsDelegate = eventsDelegate
        self.bootstrapConfig = bootstrapConfig
        self.sessionConfiguration = sessionConfiguration

        if let cacheDirectoryOverride {
            self.cacheDirectory = cacheDirectoryOverride
        } else {
            // Set up cache directory in Application Support
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.cacheDirectory = appSupport.appendingPathComponent("Bunting", isDirectory: true)
        }

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
        do {
            try loadBundledSeed()
        } catch {
            BuntingLog.config.notice("No bundled seed loaded: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public API

    /// Returns the active configuration, or nil if not loaded
    func getConfiguration() -> BuntingConfiguration? {
        return activeConfig
    }

    /// Snapshot of the active configuration plus its provenance, returned in a
    /// single actor hop for the facade's @MainActor snapshots.
    struct ConfigState: Sendable {
        let configuration: BuntingConfiguration?
        let source: ConfigSource?
        let signatureVerified: Bool
    }

    func getConfigState() -> ConfigState {
        return ConfigState(
            configuration: activeConfig,
            source: activeSource,
            signatureVerified: activeSignatureVerified
        )
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

        sessionConfiguration.urlCache = nil
        let session = URLSession(configuration: sessionConfiguration)

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

        // Obtain the detached JWS and verify it against the exact config bytes
        // we just fetched. Preferred transport is the x-bunting-signature
        // response header (saves a request); fall back to the sibling
        // config.json.sig object.
        let jws: String
        if let headerSig = httpResponse.value(forHTTPHeaderField: SignatureTransport.headerName) {
            jws = headerSig
        } else {
            let sigURL = SignatureTransport.sigURL(for: url)
            guard
                let (sigData, sigResponse) = try? await session.data(from: sigURL),
                (sigResponse as? HTTPURLResponse)?.statusCode == 200,
                let sigString = String(data: sigData, encoding: .utf8)
            else {
                await notifyDidVerifySignature(success: false)
                await notifyDidCompleteFetch(success: false, error: BuntingError.signatureVerificationFailed)
                throw BuntingError.signatureVerificationFailed
            }
            jws = sigString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            try JWSVerifier.verifyDetached(
                jws: jws,
                payload: data,
                publicKeys: bootstrapConfig.publicKeys
            )
            await notifyDidVerifySignature(success: true)
        } catch {
            await notifyDidVerifySignature(success: false)
            await notifyDidCompleteFetch(success: false, error: BuntingError.signatureVerificationFailed)
            throw BuntingError.signatureVerificationFailed
        }

        // Parse configuration
        let decoder = JSONDecoder()
        let newConfig = try decoder.decode(BuntingConfiguration.self, from: data)

        // Save to cache (signature first, then config)
        try saveToCache(data, signature: jws)

        // Update active config
        activeConfig = newConfig
        activeSource = .fetched
        activeSignatureVerified = true
        lastTTLRefresh = Date()

        // Update cached headers
        cachedETag = httpResponse.value(forHTTPHeaderField: "ETag")
        cachedLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        try saveMetadata()

        // Notify successful fetch completion
        await notifyDidCompleteFetch(success: true, error: nil)
    }

    // MARK: - Caching

    private func loadCachedConfig() throws {
        let configURL = cacheDirectory.appendingPathComponent(configFileName)
        let signatureURL = cacheDirectory.appendingPathComponent(signatureFileName)

        guard fileManager.fileExists(atPath: configURL.path) else {
            BuntingLog.config.notice("Cached config not found at path: \(configURL.path, privacy: .private)")
            throw BuntingError.invalidConfiguration
        }

        let data = try Data(contentsOf: configURL)

        // Re-verify the persisted signature over the exact cached bytes. A
        // missing or failing signature means the cache can never verify again
        // with the shipped key set — delete it so we don't retry every launch,
        // and fall through to the bundled seed.
        guard
            let sigData = try? Data(contentsOf: signatureURL),
            let jws = String(data: sigData, encoding: .utf8)
        else {
            BuntingLog.config.notice("Cached config has no signature — discarding cache")
            deleteCacheFiles()
            throw BuntingError.signatureVerificationFailed
        }

        do {
            try JWSVerifier.verifyDetached(
                jws: jws,
                payload: data,
                publicKeys: bootstrapConfig.publicKeys
            )
        } catch {
            BuntingLog.config.error("Cached config failed signature re-verification — discarding cache")
            deleteCacheFiles()
            Task {
                await notifyDidVerifySignature(success: false)
            }
            throw BuntingError.signatureVerificationFailed
        }

        let decoder = JSONDecoder()
        let config = try decoder.decode(BuntingConfiguration.self, from: data)
        activeConfig = config
        activeSource = .cache
        activeSignatureVerified = true

        // Load metadata
        loadMetadata()

        // Notify delegate
        Task {
            await notifyDidLoadCachedConfig(version: config.configVersion)
        }

        BuntingLog.config.info("Loaded cached config version: \(config.configVersion, privacy: .public)")
    }

    private func loadBundledSeed() throws {
        // Look for BuntingConfig.json in the main bundle
        guard let bundleURL = Bundle.main.url(forResource: "BuntingConfig", withExtension: "json")
        else {
            BuntingLog.config.notice("No bundled BuntingConfig.json found in main bundle")
            throw BuntingError.invalidConfiguration
        }

        do {
            BuntingLog.config.info("Found bundled BuntingConfig.json at: \(bundleURL.path, privacy: .private)")
            let data = try Data(contentsOf: bundleURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(BuntingConfiguration.self, from: data)
            activeConfig = config
            activeSource = .seed
            activeSignatureVerified = false

            // Notify delegate
            Task {
                await notifyDidLoadCachedConfig(version: config.configVersion)
            }

            BuntingLog.config.info("Loaded bundled seed config version: \(config.configVersion, privacy: .public)")
        } catch {
            BuntingLog.config.error("Failed to decode bundled BuntingConfig.json: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Persists the config bytes and their detached JWS. The signature is
    /// written first: a crash between the two writes leaves a stale-config /
    /// new-signature pair that simply fails re-verification on next launch —
    /// never a silently unverified config.
    private func saveToCache(_ data: Data, signature: String) throws {
        let configURL = cacheDirectory.appendingPathComponent(configFileName)
        let signatureURL = cacheDirectory.appendingPathComponent(signatureFileName)
        try Data(signature.utf8).write(to: signatureURL, options: .atomic)
        try data.write(to: configURL, options: .atomic)
    }

    private func deleteCacheFiles() {
        try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(configFileName))
        try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(signatureFileName))
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
