// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bunting",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
    ],
    products: [
        .library(
            name: "Bunting",
            targets: ["Bunting"]
        ),
        .executable(
            name: "bunting-cli",
            targets: ["bunting-cli"]
        ),
        .executable(
            name: "bunting-codegen",
            targets: ["bunting-codegen"]
        ),
        .plugin(
            name: "FetchConfigPlugin",
            targets: ["FetchConfigPlugin"]
        ),
        .plugin(
            name: "BuntingCodegenPlugin",
            targets: ["BuntingCodegenPlugin"]
        ),
    ],
    dependencies: [
        // No external dependencies for v1 - using only platform frameworks
    ],
    targets: [
        .target(
            name: "Bunting",
            dependencies: [],
            path: "Sources/Bunting"
        ),
        .testTarget(
            name: "BuntingTests",
            dependencies: ["Bunting"],
            path: "Tests/BuntingTests"
        ),

        // Command-line tool for fetching configuration
        .executableTarget(
            name: "bunting-cli",
            dependencies: [],
            path: "Sources/bunting-cli"
        ),

        // Code generation executable
        .executableTarget(
            name: "bunting-codegen",
            dependencies: [],
            path: "Sources/bunting-codegen"
        ),

        // Command plugin to fetch latest config
        .plugin(
            name: "FetchConfigPlugin",
            capability: .command(
                intent: .custom(
                    verb: "fetch-config",
                    description: "Fetches the latest Bunting configuration from your backend"
                )
            ),
            dependencies: ["bunting-cli"]
        ),

        // Build tool plugin to generate strongly-typed flag accessors
        .plugin(
            name: "BuntingCodegenPlugin",
            capability: .buildTool(),
            dependencies: ["bunting-codegen"]
        ),
    ]
)
