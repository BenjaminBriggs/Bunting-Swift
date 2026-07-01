import Foundation
import Testing

/// Runs the built `bunting-cli` executable as a subprocess. bunting-cli's fetch
/// step is network-only (no offline/local-input mode — `main.swift` always
/// resolves the plist's endpoint_url via `URLSession` and issues a real HTTP
/// GET), so the network-touching tests here point it at a `LocalFixtureServer`
/// on 127.0.0.1 instead of a real backend. Argument/plist validation paths that
/// fail before any network call are tested directly, no server needed.
struct CLITests {

    private struct PlistPublicKey: Encodable {
        let kid: String
        let pem: String
    }

    private struct PlistConfig: Encodable {
        let endpoint_url: String
        let public_keys: [PlistPublicKey]
    }

    private func writePlist(endpointURL: String, publicKeys: [(kid: String, pem: String)], to url: URL)
        throws
    {
        let config = PlistConfig(
            endpoint_url: endpointURL,
            public_keys: publicKeys.map { PlistPublicKey(kid: $0.kid, pem: $0.pem) })
        let data = try PropertyListEncoder().encode(config)
        try data.write(to: url)
    }

    private func runCLI(arguments: [String]) throws -> SubprocessTestSupport.ProcessResult {
        let executable = try SubprocessTestSupport.executableURL(named: "bunting-cli")
        return try SubprocessTestSupport.run(executable, arguments: arguments)
    }

    // MARK: - Exit codes (mirrors bunting-cli's documented contract)

    private enum ExitCode {
        static let usageOrPlistError: Int32 = 1
        static let networkError: Int32 = 2
        static let signatureError: Int32 = 3
        static let decodeError: Int32 = 4
    }

    // MARK: - Argument / plist validation (no network)

    @Test
    func missingArguments_printsUsageAndExitsWithUsageError() throws {
        let result = try runCLI(arguments: [])
        #expect(result.exitCode == ExitCode.usageOrPlistError)
        #expect(result.stdout.contains("USAGE:"))
    }

    @Test
    func missingPlistFile_exitsWithUsageError() throws {
        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let missingPlist = directory.appendingPathComponent("DoesNotExist.plist")
            let result = try runCLI(arguments: [missingPlist.path])
            #expect(result.exitCode == ExitCode.usageOrPlistError)
            #expect(result.stdout.contains("❌ Error"))
        }
    }

    @Test
    func malformedPlist_exitsWithUsageError() throws {
        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            try Data("this is not a plist".utf8).write(to: plistURL)
            let result = try runCLI(arguments: [plistURL.path])
            #expect(result.exitCode == ExitCode.usageOrPlistError)
            #expect(result.stdout.contains("❌ Error"))
        }
    }

    @Test
    func invalidEndpointURLInPlist_exitsWithUsageError() throws {
        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            // An empty endpoint_url makes URL(string:) return nil, which is a
            // plist/argument-validation failure distinct from a network error.
            try writePlist(
                endpointURL: "", publicKeys: [(kid: "k", pem: "unused")], to: plistURL)
            let result = try runCLI(arguments: [plistURL.path])
            #expect(result.exitCode == ExitCode.usageOrPlistError)
            #expect(result.stdout.contains("Invalid URL"))
        }
    }

    // MARK: - Verify path: header transport, valid signature

    @Test
    func validSignedConfigWithCorrectKey_verifiesAndSavesSuccessfully() throws {
        let server = try LocalFixtureServer(routes: [
            "/config.json": LocalFixtureServer.Response(
                statusCode: 200,
                headers: ["x-bunting-signature": SignedConfigFixture.jws],
                body: SignedConfigFixture.configData)
        ])
        defer { server.stop() }

        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            let outputURL = directory.appendingPathComponent("Output.json")
            try writePlist(
                endpointURL: "http://127.0.0.1:\(server.port)/config.json",
                publicKeys: [(kid: "test-key", pem: SignedConfigFixture.pem)],
                to: plistURL)

            let result = try runCLI(arguments: [plistURL.path, outputURL.path])

            #expect(result.exitCode == 0)
            #expect(result.stdout.contains("✅ Signature verified"))
            #expect(result.stdout.contains("✨ Success!"))
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
            let savedBytes = try Data(contentsOf: outputURL)
            #expect(savedBytes == SignedConfigFixture.configData)
        }
    }

    // MARK: - Verify path: .sig fallback transport

    @Test
    func noHeaderSignature_fallsBackToSigFileAndVerifies() throws {
        let server = try LocalFixtureServer(routes: [
            "/config.json": LocalFixtureServer.Response(
                statusCode: 200, body: SignedConfigFixture.configData),
            "/config.json.sig": LocalFixtureServer.Response(
                statusCode: 200, body: Data(SignedConfigFixture.jws.utf8)),
        ])
        defer { server.stop() }

        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            let outputURL = directory.appendingPathComponent("Output.json")
            try writePlist(
                endpointURL: "http://127.0.0.1:\(server.port)/config.json",
                publicKeys: [(kid: "test-key", pem: SignedConfigFixture.pem)],
                to: plistURL)

            let result = try runCLI(arguments: [plistURL.path, outputURL.path])

            #expect(result.exitCode == 0)
            #expect(result.stdout.contains(".sig fetch"))
            #expect(result.stdout.contains("✅ Signature verified"))
        }
    }

    // MARK: - Verify path: tampering and wrong key

    @Test
    func tamperedConfigBytes_signatureVerificationFails() throws {
        // The signature is valid for the fixture's original bytes, but the
        // server serves tampered bytes — the CLI must verify over the exact
        // bytes it fetched and reject.
        var tampered = SignedConfigFixture.configData
        tampered.append(0x20)

        let server = try LocalFixtureServer(routes: [
            "/config.json": LocalFixtureServer.Response(
                statusCode: 200,
                headers: ["x-bunting-signature": SignedConfigFixture.jws],
                body: tampered)
        ])
        defer { server.stop() }

        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            let outputURL = directory.appendingPathComponent("Output.json")
            try writePlist(
                endpointURL: "http://127.0.0.1:\(server.port)/config.json",
                publicKeys: [(kid: "test-key", pem: SignedConfigFixture.pem)],
                to: plistURL)

            let result = try runCLI(arguments: [plistURL.path, outputURL.path])

            #expect(result.exitCode == ExitCode.signatureError)
            #expect(result.stdout.contains("❌ Error"))
            #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
        }
    }

    @Test
    func wrongPublicKeyForKid_signatureVerificationFails() throws {
        let server = try LocalFixtureServer(routes: [
            "/config.json": LocalFixtureServer.Response(
                statusCode: 200,
                headers: ["x-bunting-signature": SignedConfigFixture.jws],
                body: SignedConfigFixture.configData)
        ])
        defer { server.stop() }

        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            let outputURL = directory.appendingPathComponent("Output.json")
            // Plist registers the secondary fixture's key material under the
            // primary fixture's kid ("test-key") — right kid, wrong key.
            try writePlist(
                endpointURL: "http://127.0.0.1:\(server.port)/config.json",
                publicKeys: [(kid: "test-key", pem: SignedConfigFixture.secondaryPem)],
                to: plistURL)

            let result = try runCLI(arguments: [plistURL.path, outputURL.path])

            #expect(result.exitCode == ExitCode.signatureError)
            #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
        }
    }

    // MARK: - Network error (no server listening)

    @Test
    func unreachableEndpoint_exitsWithNetworkError() throws {
        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let plistURL = directory.appendingPathComponent("BuntingConfig.plist")
            // Port 1 is reserved and nothing will ever listen on it locally.
            try writePlist(
                endpointURL: "http://127.0.0.1:1/config.json",
                publicKeys: [(kid: "k", pem: "unused")],
                to: plistURL)
            let result = try runCLI(arguments: [plistURL.path])
            #expect(result.exitCode == ExitCode.networkError)
        }
    }
}
