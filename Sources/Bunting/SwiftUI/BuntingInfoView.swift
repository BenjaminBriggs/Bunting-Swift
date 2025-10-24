//
//  BuntingInfoView.swift
//  Bunting
//
//  Read-only debug information view for Bunting configuration
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Read-only view displaying Bunting configuration status and metadata
///
/// This view provides a non-interactive display of:
/// - Configuration version and publication date
/// - Signature verification status
/// - Last fetch time and ETag
/// - Device identity (local ID)
/// - Environment configuration
///
/// Usage:
/// ```swift
/// NavigationStack {
///     BuntingInfoView()
/// }
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct BuntingInfoView: View {
    // MARK: - State

    @State private var configVersion: String?
    @State private var publishedAt: Date?
    @State private var signatureVerified = false
    @State private var localID: String = ""
    @State private var environment: String = ""
    @State private var lastFetchTime: Date?
    @State private var etag: String?

    // Flag data
    @State private var flags: [FlagInfo] = []
    @State private var overrides: [String: OverrideValue] = [:]

    // MARK: - Body

    public var body: some View {
        List {
            // MARK: - Environment Section

            Section {
                LabeledContent("Environment", value: environment)
            } header: {
                Text("Configuration")
            }

            // MARK: - Status Section

            Section {
                // Config version
                if let version = configVersion {
                    LabeledContent("Version", value: version)
                } else {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("Not loaded")
                            .foregroundStyle(.secondary)
                    }
                }

                // Publication date
                if let published = publishedAt {
                    LabeledContent("Published") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(published, style: .relative)
                            Text(published, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Signature verification status
                LabeledContent("Signature") {
                    HStack {
                        if signatureVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Verified")
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Not Verified")
                        }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Status")
            }

            // MARK: - Network Section

            Section {
                // Last fetch time
                if let lastFetch = lastFetchTime {
                    LabeledContent("Last Fetch") {
                        Text(lastFetch, style: .relative)
                    }
                } else {
                    HStack {
                        Text("Last Fetch")
                        Spacer()
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }

                // ETag
                if let etag = etag {
                    LabeledContent("ETag") {
                        Text(etag)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text("ETag is used for efficient caching with conditional GET requests.")
            }

            // MARK: - Identity Section

            Section {
                LabeledContent("Local ID") {
                    Text(localID)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Device Identity")
            } footer: {
                Text("The local ID is stored in the keychain and used for deterministic bucketing.")
            }

            if !flags.isEmpty {
                ForEach(groupedFlags.keys.sorted(), id: \.self) { namespace in
                    if let nsFlags = groupedFlags[namespace] {
                        Section {
                            ForEach(nsFlags) { flag in
                                FlagRowView(
                                    key: flag.key,
                                    displayName: flag.displayName,
                                    type: flag.type,
                                    effectiveValue: flag.effectiveValue,
                                    defaultValue: flag.defaultValue,
                                    mode: .info,
                                    hasOverride: overrides[flag.key] != nil
                                )
                            }
                        } header: {
                            Text(
                                namespace.isEmpty
                                    ? "Root Flags"
                                    : namespace.replacingOccurrences(of: "/", with: " / ")
                                        .capitalized)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bunting Info")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadInfo()
        }
        .refreshable {
            await loadInfo()
        }
    }

    // MARK: - Computed Properties

    private var groupedFlags: [String: [FlagInfo]] {
        Dictionary(grouping: flags) { flag in
            if let slashIndex = flag.key.lastIndex(of: "/") {
                return String(flag.key[..<slashIndex])
            }
            return ""
        }
    }

    // MARK: - Initializer

    public init() {}

    // MARK: - Methods

    @MainActor
    private func loadInfo() async {
        let bunting = Bunting.shared

        // Configuration metadata
        configVersion = bunting.configVersion
        publishedAt = bunting.publishedAt
        signatureVerified = bunting.signatureVerified
        environment = "\(bunting.environment)"

        // Device identity
        localID = bunting.localID.uuidString

        // Network metadata (from ConfigStore)
        // Note: These would need to be exposed by ConfigStore
        // For now, we'll leave them as optional
        lastFetchTime = nil  // TODO: Expose from ConfigStore
        etag = nil  // TODO: Expose from ConfigStore

        // Load current overrides
        overrides = bunting.getAllOverrides()

        // Load flags from configuration
        if let config = bunting.configuration {
            flags = config.flags.map { (key, flag) in
                // Get effective value by actually evaluating the flag
                let effectiveValue = getEffectiveValue(for: key, flag: flag, bunting: bunting)

                return FlagInfo(
                    key: key,
                    type: flag.type,
                    effectiveValue: effectiveValue,
                    defaultValue: getDefaultValue(for: flag, environment: bunting.environment)
                )
            }.sorted { $0.key < $1.key }
        } else {
            flags = []
        }
    }

    // MARK: - Helper Methods

    private func getEffectiveValue(for key: String, flag: Flag, bunting: Bunting) -> String {
        // Actually evaluate the flag to get the real effective value
        let defaultValue = flag.config(for: bunting.environment).default

        switch flag.type {
        case .boolean:
            let value = bunting.bool(key, default: defaultValue.boolValue ?? false)
            return value ? "true" : "false"
        case .string:
            let value = bunting.string(key, default: defaultValue.stringValue ?? "")
            return "\"\(value)\""
        case .integer:
            let value = bunting.int(key, default: defaultValue.intValue ?? 0)
            return "\(value)"
        case .double:
            let value = bunting.double(key, default: defaultValue.doubleValue ?? 0.0)
            return String(format: "%.2f", value)
        case .date:
            let value = bunting.date(key, default: defaultValue.dateValue ?? Date())
            return ISO8601DateFormatter().string(from: value)
        case .json:
            if let data = bunting.jsonData(key), let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{}"
        }
    }

    private func getDefaultValue(for flag: Flag, environment: BuntingEnvironment) -> String {
        let envConfig = flag.config(for: environment)
        return formatFlagValue(envConfig.default)
    }

    private func formatFlagValue(_ value: FlagValue) -> String {
        switch value {
        case .boolean(let bool):
            return bool ? "true" : "false"
        case .string(let str):
            return "\"\(str)\""
        case .integer(let int):
            return "\(int)"
        case .double(let double):
            return String(format: "%.2f", double)
        case .date(let date):
            return ISO8601DateFormatter().string(from: date)
        case .json(let json):
            return json
        }
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct FlagInfo: Identifiable {
    let key: String
    let type: FlagType
    let effectiveValue: String
    let defaultValue: String

    var id: String { key }

    var displayName: String {
        if let slashIndex = key.lastIndex(of: "/") {
            let afterSlash = key.index(after: slashIndex)
            return String(key[afterSlash...])
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        return
            key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// unified row view now provided by FlagRowView

#Preview {
    NavigationStack {
        BuntingInfoView()
    }
}

#Preview {
    NavigationStack {
        BuntingInfoView()
    }
}
