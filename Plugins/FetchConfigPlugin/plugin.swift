import Foundation
import PackagePlugin

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin
#endif

/// Command Plugin: Fetch Latest Bunting Config
///
/// This plugin allows developers to fetch the latest configuration from their
/// Bunting backend directly from Xcode.
///
/// Usage:
/// 1. Right-click on your project/package in Xcode
/// 2. Select "Fetch Latest Bunting Config" from the plugin menu
/// 3. The plugin will download and verify the config, saving it to your project
///
/// Requirements:
/// - BuntingConfig.plist must exist in your project root or Resources/
/// - The endpoint must be accessible
/// - Configuration must have a valid JWS signature
@main
struct FetchConfigPlugin: CommandPlugin {

    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let rootDirectory = context.package.directoryURL
        let tool = try context.tool(named: "bunting-cli")
        try await runPlugin(
            rootDirectory: rootDirectory,
            pluginWorkDirectory: context.pluginWorkDirectoryURL,
            executableURL: tool.url
        )
    }
}

#if canImport(XcodeProjectPlugin)
extension FetchConfigPlugin: XcodeCommandPlugin {
    func performCommand(
        context: XcodePluginContext,
        arguments: [String]
    ) {
        do {
            let rootDirectory = context.xcodeProject.directoryURL
            let workingDirectory = context.pluginWorkDirectoryURL
            let toolURL = try context.tool(named: "bunting-cli").url

            Task.detached(priority: .userInitiated) { [rootDirectory, workingDirectory, toolURL] in
                do {
                    try await runPlugin(
                        rootDirectory: rootDirectory,
                        pluginWorkDirectory: workingDirectory,
                        executableURL: toolURL
                    )
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
#endif

extension FetchConfigPlugin {
    func runPlugin(
        rootDirectory: URL,
        pluginWorkDirectory: URL,
        executableURL: URL
    ) async throws {
        // Find BuntingConfig.plist
        let plistURL = try findBuntingConfigPlist(in: rootDirectory)

        print("📦 Bunting: Fetch Latest Config")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        print("Found BuntingConfig.plist at:")
        print("  \(plistURL.path)")
        print("")

        // Determine output path
        let outputURL = rootDirectory.appending(path: "BuntingConfig.json")

        // Run the CLI tool
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [plistURL.path, outputURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print(output)
        }

        if process.terminationStatus != 0 {
            throw PluginError.commandFailed(status: process.terminationStatus)
        }

        print("")
        print("✅ Config saved to: \(outputURL.path)")
        print("")
        print("Next steps:")
        print("  • Add BuntingConfig.json to your Xcode project")
        print("  • Use it for code generation or reference")
        print("  • Run the codegen plugin to generate typed accessors")
        print("")
    }

    private func findBuntingConfigPlist(in directory: URL) throws -> URL {
        // Check common locations
        let possiblePaths = [
            directory.appending(path: "BuntingConfig.plist"),
            directory.appending(path: "Resources/BuntingConfig.plist"),
            directory.appending(path: "Example/BuntingExample/BuntingConfig.plist"),
        ]

        for url in possiblePaths {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        throw PluginError.plistNotFound(searchedPaths: possiblePaths.map { $0.path })
    }
}

enum PluginError: LocalizedError {
    case plistNotFound(searchedPaths: [String])
    case commandFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .plistNotFound(let paths):
            return """
                Could not find BuntingConfig.plist in any of these locations:
                \(paths.map { "  • \($0)" }.joined(separator: "\n"))

                Please ensure BuntingConfig.plist exists in your project.
                """
        case .commandFailed(let status):
            return "bunting-cli command failed with status \(status)"
        }
    }
}

