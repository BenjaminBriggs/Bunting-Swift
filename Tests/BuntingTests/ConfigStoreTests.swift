import BuntingVerify
import XCTest

@testable import Bunting

/// End-to-end ConfigStore behavior over a stubbed URL layer: signature
/// transport (x-bunting-signature header first, config.json.sig fallback),
/// signature persistence next to the cache, and re-verification on cache load.
///
/// The fixture triple (config bytes, SPKI public key, detached JWS) was
/// generated offline with openssl using the same detached RFC 7797 form the
/// admin publishes.
final class ConfigStoreTests: XCTestCase {

    // Fixture blobs live in SignedConfigFixture (shared with CLITests) —
    // aliased here under this file's existing names to keep the rest of the
    // file (and every downstream reference below) unchanged.

    // base64 of the exact config.json bytes that were signed.
    private let configB64 = SignedConfigFixture.configB64

    // base64 of the SPKI public-key PEM matching the JWS below.
    private let pemB64 = SignedConfigFixture.pemB64

    private let jws = SignedConfigFixture.jws

    // A second fixture: a schema_version:2 payload, signed with a different
    // key (kid "test-key-2"), used to exercise the "signed but undecodable"
    // fallback path.
    private let undecodableConfigB64 = SignedConfigFixture.secondaryConfigB64

    private let undecodablePemB64 = SignedConfigFixture.secondaryPemB64

    private let undecodableJWS = SignedConfigFixture.secondaryJWS

    private let configURLString = "https://cdn.example.test/test-app/config.json"
    private var sigURLString: String { configURLString + ".sig" }

    private var configData: Data { Data(base64Encoded: configB64)! }
    private var pem: String { String(data: Data(base64Encoded: pemB64)!, encoding: .utf8)! }
    private var undecodableConfigData: Data { Data(base64Encoded: undecodableConfigB64)! }
    private var undecodablePem: String {
        String(data: Data(base64Encoded: undecodablePemB64)!, encoding: .utf8)!
    }

    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuntingConfigStoreTests-\(UUID().uuidString)", isDirectory: true)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore(kid: String = "test-key") throws -> ConfigStore {
        let bootstrap = BootstrapConfig(
            endpointURL: configURLString,
            publicKeys: [PublicKeyInfo(kid: kid, pem: pem)],
            fetchPolicy: FetchPolicy(minIntervalSeconds: 0, hardTTLDays: 30)
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return try ConfigStore(
            bootstrapConfig: bootstrap,
            sessionConfiguration: sessionConfiguration,
            cacheDirectoryOverride: cacheDirectory
        )
    }

    /// A store whose key set can verify both the valid fixture (kid
    /// "test-key") and the signed-but-undecodable fixture (kid "test-key-2").
    private func makeStoreWithBothKeys() throws -> ConfigStore {
        let bootstrap = BootstrapConfig(
            endpointURL: configURLString,
            publicKeys: [
                PublicKeyInfo(kid: "test-key", pem: pem),
                PublicKeyInfo(kid: "test-key-2", pem: undecodablePem),
            ],
            fetchPolicy: FetchPolicy(minIntervalSeconds: 0, hardTTLDays: 30)
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return try ConfigStore(
            bootstrapConfig: bootstrap,
            sessionConfiguration: sessionConfiguration,
            cacheDirectoryOverride: cacheDirectory
        )
    }

    private var cachedConfigURL: URL { cacheDirectory.appendingPathComponent("config_v1.json") }
    private var cachedSigURL: URL { cacheDirectory.appendingPathComponent("config_v1.json.sig") }

    // MARK: - Transport

    func testHeaderTransportSkipsSigFetch() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws, "ETag": "\"abc\""],
                body: configData
            )
        ])

        let store = try makeStore()
        try await store.refresh()

        let state = await store.getConfigState()
        XCTAssertEqual(state.configuration?.configVersion, "2026-07-01.1")
        XCTAssertEqual(state.source, .fetched)
        XCTAssertTrue(state.signatureVerified)
        XCTAssertEqual(StubURLProtocol.requestLog, [configURLString], "header transport must not fetch .sig")
    }

    func testSigFileFallbackWhenHeaderAbsent() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(status: 200, headers: [:], body: configData),
            sigURLString: .init(status: 200, headers: [:], body: Data(jws.utf8)),
        ])

        let store = try makeStore()
        try await store.refresh()

        let state = await store.getConfigState()
        XCTAssertEqual(state.source, .fetched)
        XCTAssertTrue(state.signatureVerified)
        XCTAssertEqual(StubURLProtocol.requestLog, [configURLString, sigURLString])
    }

    func testFailsWhenBothTransportsAbsent() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(status: 200, headers: [:], body: configData)
            // no .sig route -> stub answers 404
        ])

        let store = try makeStore()
        do {
            try await store.refresh()
            XCTFail("Expected signatureVerificationFailed")
        } catch let error as BuntingError {
            guard case .signatureVerificationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let state = await store.getConfigState()
        XCTAssertNil(state.configuration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedConfigURL.path), "nothing may be cached")
    }

    func testTamperedPayloadRejectedAndNotCached() async throws {
        var tampered = configData
        tampered.append(0x20)
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws],
                body: tampered
            )
        ])

        let store = try makeStore()
        do {
            try await store.refresh()
            XCTFail("Expected signatureVerificationFailed")
        } catch let error as BuntingError {
            guard case .signatureVerificationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let state = await store.getConfigState()
        XCTAssertNil(state.configuration)
        XCTAssertFalse(state.signatureVerified)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedConfigURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedSigURL.path))
    }

    // MARK: - Cache persistence + re-verification

    func testCacheRoundTripReVerifiesOnLoad() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws],
                body: configData
            )
        ])

        let storeA = try makeStore()
        try await storeA.refresh()
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedConfigURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedSigURL.path))

        // Fresh store on the same cache directory, no network routes at all.
        StubURLProtocol.setRoutes([:])
        let storeB = try makeStore()
        await storeB.loadCachedConfigIfNeeded()

        let state = await storeB.getConfigState()
        XCTAssertEqual(state.configuration?.configVersion, "2026-07-01.1")
        XCTAssertEqual(state.source, .cache)
        XCTAssertTrue(state.signatureVerified, "cache load must re-verify the persisted signature")
    }

    func testTamperedCacheIsDiscarded() async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        var tampered = configData
        tampered.append(0x20)
        try tampered.write(to: cachedConfigURL)
        try Data(jws.utf8).write(to: cachedSigURL)

        let store = try makeStore()
        await store.loadCachedConfigIfNeeded()

        let state = await store.getConfigState()
        XCTAssertNil(state.configuration, "tampered cache must not activate")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedConfigURL.path), "tampered cache must be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedSigURL.path))
    }

    func testCacheWithoutSignatureIsDiscarded() async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try configData.write(to: cachedConfigURL)

        let store = try makeStore()
        await store.loadCachedConfigIfNeeded()

        let state = await store.getConfigState()
        XCTAssertNil(state.configuration, "unsigned cache must not activate")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedConfigURL.path))
    }

    func testCacheWithWrongKeyIsDiscarded() async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try configData.write(to: cachedConfigURL)
        try Data(jws.utf8).write(to: cachedSigURL)

        // Bootstrap whose key set does not contain the signing kid.
        let store = try makeStore(kid: "some-other-kid")
        await store.loadCachedConfigIfNeeded()

        let state = await store.getConfigState()
        XCTAssertNil(state.configuration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedConfigURL.path))
    }

    // MARK: - lastFetchTime / etag exposure

    func testSuccessfulFetchSetsLastFetchTimeAndETag() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws, "ETag": "\"abc123\""],
                body: configData
            )
        ])

        let store = try makeStore()
        let before = Date()
        try await store.refresh()
        let after = Date()

        let state = await store.getConfigState()
        XCTAssertEqual(state.etag, "\"abc123\"")
        let fetchTime = try XCTUnwrap(state.lastFetchTime)
        XCTAssertTrue(fetchTime >= before && fetchTime <= after)
    }

    /// A 304 proves contact with the server and confirms our cached config
    /// is still current — it counts as a successful fetch for display
    /// purposes, so it must advance `lastFetchTime`. The ETag from the prior
    /// 200 response is retained since the 304 doesn't carry a new one.
    func testNotModifiedResponseUpdatesLastFetchTimeAndRetainsETag() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws, "ETag": "\"abc123\""],
                body: configData
            )
        ])
        let store = try makeStore()
        try await store.refresh()
        let firstState = await store.getConfigState()
        let firstFetchTime = try XCTUnwrap(firstState.lastFetchTime)

        try await Task.sleep(nanoseconds: 10_000_000)

        StubURLProtocol.setRoutes([
            configURLString: .init(status: 304, headers: [:], body: Data())
        ])
        try await store.refresh()

        let secondState = await store.getConfigState()
        let secondFetchTime = try XCTUnwrap(secondState.lastFetchTime)
        XCTAssertGreaterThan(
            secondFetchTime, firstFetchTime,
            "304 must update lastFetchTime — it proves contact with the server")
        XCTAssertEqual(secondState.etag, "\"abc123\"", "etag from prior 200 must be retained on 304")
    }

    // MARK: - Undecodable artifact regression (item 5)

    /// A fetched artifact that passes signature verification but fails to
    /// decode (here: schema_version 2, which this SDK rejects) must not
    /// replace the cache or the active configuration — the SDK keeps serving
    /// the last-known-good config.
    func testSignedButUndecodableArtifactDoesNotReplaceCache() async throws {
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: jws],
                body: configData
            )
        ])

        let store = try makeStoreWithBothKeys()
        try await store.refresh()

        let goodState = await store.getConfigState()
        XCTAssertEqual(goodState.configuration?.configVersion, "2026-07-01.1")
        let cachedBytesBefore = try Data(contentsOf: cachedConfigURL)

        // Serve a config that verifies (signed with a key this store trusts)
        // but fails to decode.
        StubURLProtocol.setRoutes([
            configURLString: .init(
                status: 200,
                headers: [SignatureTransport.headerName: undecodableJWS],
                body: undecodableConfigData
            )
        ])

        do {
            try await store.refresh()
            XCTFail("Expected a decoding error")
        } catch is DecodingError {
            // expected
        }

        let stateAfter = await store.getConfigState()
        XCTAssertEqual(stateAfter.configuration?.configVersion, "2026-07-01.1", "cache/seed must keep serving")
        XCTAssertEqual(stateAfter.source, .fetched)

        let cachedBytesAfter = try Data(contentsOf: cachedConfigURL)
        XCTAssertEqual(cachedBytesBefore, cachedBytesAfter, "on-disk cache must not be overwritten")
    }
}

// MARK: - URLProtocol stub

/// Serves canned responses from a static route table and records every
/// requested URL. Unrouted URLs get a 404.
final class StubURLProtocol: URLProtocol {
    struct Route {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Route] = [:]
    nonisolated(unsafe) private static var log: [String] = []

    static func setRoutes(_ newRoutes: [String: Route]) {
        lock.lock()
        routes = newRoutes
        log = []
        lock.unlock()
    }

    static func reset() {
        setRoutes([:])
    }

    static var requestLog: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    private static func route(recording urlString: String) -> Route? {
        lock.lock()
        defer { lock.unlock() }
        log.append(urlString)
        return routes[urlString]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let route = Self.route(recording: url.absoluteString)
        let status = route?.status ?? 404
        let headers = route?.headers ?? [:]
        let body = route?.body ?? Data()

        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
