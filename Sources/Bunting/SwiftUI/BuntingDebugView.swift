//
//  BuntingDebugView.swift
//  Bunting
//
//  Interactive debug panel for Bunting feature flags
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Interactive debug panel for testing and troubleshooting Bunting
///
/// This view provides comprehensive debugging tools:
/// - Configuration status and metadata (like BuntingInfoView)
/// - Manual refresh trigger
/// - Device identity viewing and reset
/// - Per-flag override management with type-specific controls
/// - Effective value display with source indication
///
/// Usage:
/// ```swift
/// NavigationStack {
///     BuntingDebugView()
/// }
/// ```
///
/// Note: This view is intended for development and testing only.
/// Consider gating access behind a debug menu or build configuration.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct BuntingDebugView: View {
    // MARK: - State

    @State private var configVersion: String?
    @State private var publishedAt: Date?
    @State private var signatureVerified = false
    @State private var localID: String = ""
    @State private var environment: String = ""

    @State private var isRefreshing = false
    @State private var showClearOverridesConfirmation = false

    // Flag data
    @State private var flags: [FlagInfo] = []
    @State private var overrides: [String: OverrideValue] = [:]
    @State private var searchText: String = ""

    // MARK: - Body

    @State private var showingDetails = false

    public var body: some View {
        List {
            // MARK: - Flags Section

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
                                    mode: .debug,
                                    hasOverride: overrides[flag.key] != nil,
                                    sourceBadgeTitle: flag.source.displayName,
                                    sourceBadgeColor: flag.source.color,
                                    onSetOverride: { value in
                                        setOverride(key: flag.key, value: value)
                                    },
                                    onClearOverride: {
                                        clearOverride(key: flag.key)
                                    }
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
        .navigationTitle("Bunting Debug")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: trailingToolbarPlacement) {
                if overrides.isEmpty == false {
                    Button {
                        showClearOverridesConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .confirmationDialog(
                        "Clear \(overrides.count) Overrides?",
                        isPresented: $showClearOverridesConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive) { clearAllOverrides() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all \(overrides.count) local override(s) and restore backend values.")
                    }
                }
            }
             
            ToolbarItemGroup(placement: trailingToolbarPlacement) {
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            BuntingDetailsSheet(
                environment: BuntingEnvironment(rawValue: environment) ?? .production,
                configVersion: configVersion,
                publishedAt: publishedAt,
                signatureVerified: signatureVerified,
                localID: localID,
                lastFetchTime: nil,
                etag: nil,
                showResetIdentity: true,
                onResetIdentity: {
                    Task { await resetIdentity() }
                },
                onRefresh: {
                    await refreshConfig()
                },
                onChangeEnvironment: { newEnv in
                    Bunting.shared.setEnvironment(newEnv)
                    environment = newEnv.rawValue
                    Task { await loadDebugInfo() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .searchable(text: $searchText, placement: searchFieldPlacement, prompt: "Search flags")
        .task {
            await loadDebugInfo()
        }
        .refreshable {
            await loadDebugInfo()
        }
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .navigationBarTrailing
        #else
            return .automatic
        #endif
    }

    private var searchFieldPlacement: SearchFieldPlacement {
        #if os(iOS)
            return .navigationBarDrawer
        #else
            return .automatic
        #endif
    }

    // MARK: - Computed Properties

    private var filteredFlags: [FlagInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return flags }
        let q = query.lowercased()
        return flags.filter { $0.displayName.lowercased().contains(q) }
    }

    private var groupedFlags: [String: [FlagInfo]] {
        Dictionary(grouping: filteredFlags) { flag in
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
    private func loadDebugInfo() {
        let bunting = Bunting.shared

        // Configuration metadata
        configVersion = bunting.configVersion
        publishedAt = bunting.publishedAt
        signatureVerified = bunting.signatureVerified
        environment = "\(bunting.environment)"
        localID = bunting.localID.uuidString

        // Load current overrides
        overrides = bunting.getAllOverrides()

        // Load flags from configuration
        if let config = bunting.configuration {
            flags = config.flags.map { (key, flag) in
                // Get effective value by actually evaluating the flag
                let effectiveValue = getEffectiveValue(for: key, flag: flag, bunting: bunting)
                let source: FlagSource = overrides[key] != nil ? .override : .evaluated

                return FlagInfo(
                    key: key,
                    type: flag.type,
                    effectiveValue: effectiveValue,
                    source: source,
                    defaultValue: getDefaultValue(for: flag, environment: bunting.environment)
                )
            }.sorted { $0.key < $1.key }
        } else {
            flags = []
        }
    }

    @MainActor
    private func refreshConfig() async {
        isRefreshing = true
        await Bunting.shared.refresh()
        await loadDebugInfo()
        isRefreshing = false
    }

    @MainActor
    private func resetIdentity() async {
        try? await Bunting.shared.resetIdentity()
        await loadDebugInfo()
    }

    @MainActor
    private func setOverride(key: String, value: Any?) {
        Bunting.shared.setOverride(key, value: value)
        Task {
            await loadDebugInfo()
        }
    }

    @MainActor
    private func clearOverride(key: String) {
        Bunting.shared.clearOverride(key)
        Task {
            await loadDebugInfo()
        }
    }

    @MainActor
    private func clearAllOverrides() {
        Bunting.shared.clearAllOverrides()
        loadDebugInfo()
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
    let source: FlagSource
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

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private enum FlagSource {
    case override
    case evaluated

    var displayName: String {
        switch self {
        case .override: return "Override"
        case .evaluated: return "Evaluated"
        }
    }

    var color: Color {
        switch self {
        case .override: return .orange
        case .evaluated: return .green
        }
    }
}

#Preview {
    NavigationStack {
        BuntingDebugView()
    }
}
