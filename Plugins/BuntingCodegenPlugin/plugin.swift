import Foundation
import PackagePlugin

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin
#endif

/// Build Tool Plugin: Generate Strongly-Typed Flag Accessors
///
/// This plugin automatically generates Swift code with strongly-typed accessors
/// for your feature flags during the build process.
///
/// How it works:
/// 1. Reads BuntingConfig.json (seed configuration)
/// 2. Parses flag definitions
/// 3. Generates nested Swift namespaces from flag keys
/// 4. Creates typed accessor properties with default values
///
/// Example:
///   Flag: "store/use_new_paywall_design" (boolean, default: false)
///   Generated: Bunting.shared.store.useNewPaywallDesign -> Bool
///
/// The generated code allows compile-time type safety and autocomplete
/// while runtime evaluation still uses the dynamic backend configuration.
@main
struct BuntingCodegenPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only run for source targets
        guard target is SourceModuleTarget else {
            return []
        }

        let rootDirectory = context.package.directoryURL
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "BuntingGenerated.swift")
        let tool = try context.tool(named: "bunting-codegen")

        return try createCommands(rootDirectory: rootDirectory, outputURL: outputURL, tool: tool)
    }
}

#if canImport(XcodeProjectPlugin)
    extension BuntingCodegenPlugin: XcodeBuildToolPlugin {
        func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws
            -> [Command]
        {
            let rootDirectory = context.xcodeProject.directoryURL
            let outputURL = context.pluginWorkDirectoryURL.appending(path: "BuntingGenerated.swift")
            let tool = try context.tool(named: "bunting-codegen")

            return try createCommands(
                rootDirectory: rootDirectory, outputURL: outputURL, tool: tool)
        }
    }
#endif

extension BuntingCodegenPlugin {
    func createCommands(rootDirectory: URL, outputURL: URL, tool: PluginContext.Tool) throws
        -> [Command]
    {
        // Try to find BuntingConfig.json (seed configuration)
        let configURL = try? findBuntingConfigJSON(in: rootDirectory)

        if configURL == nil {
            // Config not found - generate a fallback file
            print("ℹ️  Bunting: BuntingConfig.json not found - generating fallback accessors")
            print(
                "   Run 'swift package plugin fetch-config' to enable strongly-typed flag accessors"
            )
        }

        // Always create the codegen command - it will handle missing config gracefully
        return [
            .buildCommand(
                displayName: "Generating Bunting flag accessors",
                executable: tool.url,
                arguments: [
                    configURL?.path ?? "",  // Empty string signals "no config"
                    outputURL.path,
                ],
                inputFiles: configURL.map { [$0] } ?? [],
                outputFiles: [outputURL]
            )
        ]
    }

    private func findBuntingConfigJSON(in directory: URL) throws -> URL {
        let fileManager = FileManager.default

        // Check for config file in common locations
        let possiblePaths = [
            directory.appending(path: "BuntingConfig.json"),
            directory.appending(path: "Resources/BuntingConfig.json"),
            directory.appending(path: "Sources/BuntingConfig.json"),
            // Also check in Example app directories (for development)
            directory.appending(path: "Example/BuntingExample/BuntingConfig.json"),
            directory.appending(path: "Example/BuntingConfig.json"),
        ]

        // Check predefined paths first (faster)
        for url in possiblePaths {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        // Also search in app targets (for Xcode projects with app structure)
        if let enumerator = fileManager.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "BuntingConfig.json" {
                    // Don't search too deep (max 4 levels to catch Example/BuntingExample/)
                    let depth = fileURL.pathComponents.count - directory.pathComponents.count
                    if depth <= 4 {
                        return fileURL
                    }
                }
            }
        }

        // Config not found - provide helpful error
        throw PluginError.configNotFound(searchedPaths: possiblePaths.map { $0.path })
    }
}

enum PluginError: LocalizedError {
    case configNotFound(searchedPaths: [String])

    var errorDescription: String? {
        switch self {
        case .configNotFound(let paths):
            return """
                ❌ BuntingConfig.json not found

                The Bunting code generation plugin requires a seed configuration file to generate
                strongly-typed flag accessors.

                Searched in:
                \(paths.map { "  • \($0)" }.joined(separator: "\n"))

                📥 How to get BuntingConfig.json:

                Option 1: Run the Fetch Config Plugin (Recommended)
                  In Xcode:
                    1. Right-click on your project in the Project Navigator
                    2. Select: Bunting → Fetch Config
                    3. This will download BuntingConfig.json from your backend
                    4. Rebuild your project

                  Command Line:
                    1. Run: swift package plugin fetch-config
                    2. This downloads BuntingConfig.json to your project root
                    3. Build normally: xcodebuild or swift build

                Option 2: Create Manually
                  1. Download your config from your Bunting admin panel
                  2. Save it as "BuntingConfig.json" in your project root
                  3. Or place it in your app target directory (e.g., BuntingExample/)
                  4. Rebuild your project

                Option 3: Use Without Code Generation
                  If you don't need strongly-typed accessors, you can use string-based flag access:
                    let value = await Bunting.shared.bool("my/flag", default: false)

                  The codegen plugin is optional - the SDK works without it!

                ℹ️  Note: The seed config is only used for generating code at compile time.
                    Your app will still fetch the latest config from your backend at runtime.

                Need help? Check: https://github.com/yourusername/bunting-sdk-swift/blob/main/PLUGINS.md
                """
        }
    }
}
