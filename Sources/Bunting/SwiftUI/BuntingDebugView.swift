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
    @State private var showResetConfirmation = false
    @State private var showClearOverridesConfirmation = false

    // Flag data
    @State private var flags: [FlagInfo] = []
    @State private var overrides: [String: OverrideValue] = [:]

    // MARK: - Body

    public var body: some View {
        List {
            // MARK: - Configuration Section

            Section {
                LabeledContent("Environment", value: environment)

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

                // Manual refresh button
                Button {
                    Task {
                        await refreshConfig()
                    }
                } label: {
                    HStack {
                        Label("Refresh Configuration", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Configuration")
            } footer: {
                Text("Configuration is fetched from the backend and verified with JWS signature.")
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

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Identity", systemImage: "arrow.clockwise")
                }
                .confirmationDialog(
                    "Reset Identity?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) {
                        Task {
                            await resetIdentity()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "This will generate a new UUID and may change cohort assignments and rollout buckets."
                    )
                }
            } header: {
                Text("Device Identity")
            } footer: {
                Text("The local ID is used for deterministic bucketing in tests and rollouts.")
            }

            // MARK: - Flags Section

            if !flags.isEmpty {
                ForEach(groupedFlags.keys.sorted(), id: \.self) { namespace in
                    if let nsFlags = groupedFlags[namespace] {
                        Section {
                            ForEach(nsFlags) { flag in
                                FlagRowView(
                                    flag: flag,
                                    override: overrides[flag.key],
                                    onOverrideChange: { value in
                                        setOverride(key: flag.key, value: value)
                                    },
                                    onOverrideClear: {
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

            // MARK: - Actions Section

            if !overrides.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showClearOverridesConfirmation = true
                    } label: {
                        Label("Clear All Overrides (\(overrides.count))", systemImage: "trash")
                    }
                    .confirmationDialog(
                        "Clear All Overrides?",
                        isPresented: $showClearOverridesConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive) {
                            clearAllOverrides()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This will remove all \(overrides.count) local override(s) and restore backend values."
                        )
                    }
                } header: {
                    Text("Actions")
                }
            }
        }
        .navigationTitle("Bunting Debug")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadDebugInfo()
        }
        .refreshable {
            await loadDebugInfo()
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
    private func loadDebugInfo() async {
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
        Task {
            await loadDebugInfo()
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
        case .evaluated: return .blue
        }
    }
}

// MARK: - Flag Row View

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct FlagRowView: View {
    let flag: FlagInfo
    let override: OverrideValue?
    let onOverrideChange: (Any?) -> Void
    let onOverrideClear: () -> Void

    @State private var isEditingOverride = false

    // Temporary edit values
    @State private var boolValue: Bool = false
    @State private var stringValue: String = ""
    @State private var intValue: Int = 0
    @State private var doubleValue: Double = 0.0
    @State private var dateValue: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flag.displayName)
                        .font(.headline)
                    Text(flag.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Source badge
                Text(flag.source.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(flag.source.color.opacity(0.2))
                    .foregroundStyle(flag.source.color)
                    .clipShape(Capsule())
            }

            // Current effective value
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(flag.effectiveValue)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Override controls
            if override != nil {
                // Has override - show clear button
                Button(role: .destructive) {
                    onOverrideClear()
                } label: {
                    Label("Clear Override", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if isEditingOverride {
                // Editing new override
                VStack(spacing: 8) {
                    overrideEditor

                    HStack {
                        Button("Cancel") {
                            isEditingOverride = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Set Override") {
                            saveOverride()
                            isEditingOverride = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // No override - show add button
                Button {
                    initializeEditorValues()
                    isEditingOverride = true
                } label: {
                    Label("Add Override", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var overrideEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Override Value")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch flag.type {
            case .boolean:
                Toggle("Enabled", isOn: $boolValue)

            case .string:
                TextField("String value", text: $stringValue)
                    .textFieldStyle(.roundedBorder)

            case .integer:
                Stepper(value: $intValue, in: -1000...1000) {
                    HStack {
                        Text("Integer")
                        Spacer()
                        Text("\(intValue)")
                            .monospacedDigit()
                    }
                }

            case .double:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Double: \(String(format: "%.2f", doubleValue))")
                        .monospacedDigit()
                    Slider(value: $doubleValue, in: 0...100)
                }

            case .date:
                DatePicker(
                    "Date", selection: $dateValue, displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)

            case .json:
                TextEditor(text: $stringValue)
                    .frame(height: 100)
                    .font(.system(.caption, design: .monospaced))
                    .padding(4)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private func initializeEditorValues() {
        // Parse the default value to initialize editor
        let defaultStr = flag.defaultValue

        switch flag.type {
        case .boolean:
            boolValue = defaultStr == "true"
        case .string:
            stringValue = defaultStr.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        case .integer:
            intValue = Int(defaultStr) ?? 0
        case .double:
            doubleValue = Double(defaultStr) ?? 0.0
        case .date:
            if let date = ISO8601DateFormatter().date(from: defaultStr) {
                dateValue = date
            }
        case .json:
            stringValue = defaultStr
        }
    }

    private func saveOverride() {
        let value: Any?

        switch flag.type {
        case .boolean:
            value = boolValue
        case .string:
            value = stringValue
        case .integer:
            value = intValue
        case .double:
            value = doubleValue
        case .date:
            value = dateValue
        case .json:
            value = stringValue
        }

        onOverrideChange(value)
    }
}

#Preview {
    NavigationStack {
        BuntingDebugView()
    }
}
