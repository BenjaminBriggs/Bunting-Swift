import Foundation

/// Shared helpers for tests that exercise the `bunting-codegen` and `bunting-cli`
/// executables as subprocesses (as opposed to linking their internals).
enum SubprocessTestSupport {

    struct ProductsDirectoryNotFound: Error {}

    /// Locates the directory containing the build products (executables, .xctest
    /// bundle) for the current test run. The test bundle sits next to the
    /// executables it needs to exercise.
    static func productsDirectory() throws -> URL {
        // Classic technique: works when tests run inside an .xctest bundle process
        // (e.g. under Xcode).
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }

        // `swift test` on this toolchain runs tests out-of-process via
        // swiftpm-testing-helper, which isn't itself part of any bundle. It's
        // invoked with `--test-bundle-path .../<Product>.xctest/Contents/MacOS/<bin>`,
        // so recover the products directory by walking each argument up to the
        // enclosing .xctest package.
        for argument in ProcessInfo.processInfo.arguments {
            var url = URL(fileURLWithPath: argument)
            while url.pathComponents.count > 1 {
                if url.pathExtension == "xctest" {
                    return url.deletingLastPathComponent()
                }
                url.deleteLastPathComponent()
            }
        }

        throw ProductsDirectoryNotFound()
    }

    static func executableURL(named name: String) throws -> URL {
        try productsDirectory().appendingPathComponent(name)
    }

    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs `executableURL` with `arguments`, capturing stdout/stderr and waiting
    /// for exit. Synchronous by design — these tests run one short-lived process
    /// at a time.
    static func run(_ executableURL: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// Creates a fresh temporary directory and hands it to `body`, removing it
    /// afterward regardless of outcome.
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bunting-subprocess-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}
