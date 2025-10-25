import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct FlagRowView: View {
    public enum Mode { case info, debug }

    let key: String
    let displayName: String
    let type: FlagType
    let effectiveValue: String
    let defaultValue: String?
    let mode: Mode
    let hasOverride: Bool
    let sourceBadgeTitle: String?
    let sourceBadgeColor: Color
    let onSetOverride: ((Any?) -> Void)?
    let onClearOverride: (() -> Void)?

    @State private var isEditingOverride = false
    @State private var boolValue: Bool = false
    @State private var stringValue: String = ""
    @State private var intValue: Int = 0
    @State private var doubleValue: Double = 0.0
    @State private var dateValue: Date = Date()
    @State private var showJSONEditor = false
    @State private var jsonEditorText: String = ""

    public init(
        key: String,
        displayName: String,
        type: FlagType,
        effectiveValue: String,
        defaultValue: String? = nil,
        mode: Mode,
        hasOverride: Bool,
        sourceBadgeTitle: String? = nil,
        sourceBadgeColor: Color = .green,
        onSetOverride: ((Any?) -> Void)? = nil,
        onClearOverride: (() -> Void)? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.type = type
        self.effectiveValue = effectiveValue
        self.defaultValue = defaultValue
        self.mode = mode
        self.hasOverride = hasOverride
        self.sourceBadgeTitle = sourceBadgeTitle
        self.sourceBadgeColor = sourceBadgeColor
        self.onSetOverride = onSetOverride
        self.onClearOverride = onClearOverride
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(displayName)
                        .font(.headline)
                    
                    if mode == .debug {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            
                Spacer()

                Text(type.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                    if mode == .debug {
                        if hasOverride {
                            Button(role: .destructive) {
                                onClearOverride?()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                initializeEditorValues()
                                if type == .json {
                                    jsonEditorText = stringValue.isEmpty ? effectiveValue : stringValue
                                    showJSONEditor = true
                                } else {
                                    isEditingOverride = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isEditingOverride == true)
                        }
                }
            }

            if isEditingOverride {
                VStack(spacing: 8) {
                        editorView
                            .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button("Cancel") { isEditingOverride = false }.buttonStyle(.bordered)
                        Spacer()
                        Button("Set Override") { saveOverride(); isEditingOverride = false }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(effectiveValue)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4)
                        .padding(8)
                    if let title = sourceBadgeTitle {
                        Text(title)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                            .background(sourceBadgeColor.opacity(0.2))
                            .foregroundStyle(sourceBadgeColor)
                            .clipShape(UnevenRoundedRectangle(topTrailingRadius: 7))
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        Rectangle()
                            .fill(sourceBadgeColor.opacity(0.2))
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showJSONEditor) {
            NavigationStack {
                JSONEditorView(text: $jsonEditorText)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Edit JSON")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showJSONEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                onSetOverride?(jsonEditorText)
                                isEditingOverride = false
                                showJSONEditor = false
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var editorView: some View {
        switch type {
        case .boolean:
            Toggle("Enabled", isOn: $boolValue)
        case .string:
            TextField("String value", text: $stringValue).textFieldStyle(.roundedBorder)
        case .integer:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Integer", value: $intValue, formatter: intFormatter)
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                Stepper(value: $intValue) {
                    HStack { Text("Value"); Spacer(); Text("\(intValue)").monospacedDigit() }
                }
            }
        case .double:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Double", value: $doubleValue, formatter: doubleFormatter)
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
            }
        case .date:
            DatePicker("Date", selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
        case .json:
            VStack(alignment: .leading, spacing: 8) {
                Text(stringValue.isEmpty ? effectiveValue : stringValue)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    jsonEditorText = stringValue.isEmpty ? effectiveValue : stringValue
                    showJSONEditor = true
                } label: {
                    Label("Edit JSON…", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Formatters
    private var intFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.allowsFloats = false
        f.generatesDecimalNumbers = false
        f.usesGroupingSeparator = false
        return f
    }

    private var doubleFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.allowsFloats = true
        f.maximumFractionDigits = 6
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f
    }

    private func initializeEditorValues() {
        let def = defaultValue ?? ""
        switch type {
        case .boolean: boolValue = def == "true"
        case .string: stringValue = def.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        case .integer: intValue = Int(def) ?? 0
        case .double: doubleValue = Double(def) ?? 0.0
        case .date: if let date = ISO8601DateFormatter().date(from: def) { dateValue = date }
        case .json: stringValue = def
        }
    }

    private func saveOverride() {
        guard let onSetOverride else { return }
        let value: Any?
        switch type {
        case .boolean: value = boolValue
        case .string: value = stringValue
        case .integer: value = intValue
        case .double: value = doubleValue
        case .date: value = dateValue
        case .json: value = stringValue
        }
        onSetOverride(value)
    }
}

#Preview("FlagRowView Variants") {
    List {
        Section("Info Mode — No Override") {
            FlagRowView(
                key: "store/use_new_paywall_design",
                displayName: "Use New Paywall Design",
                type: .boolean,
                effectiveValue: "true",
                defaultValue: "false",
                mode: .info,
                hasOverride: false
            )
            FlagRowView(
                key: "ui/welcome_message",
                displayName: "Welcome Message",
                type: .string,
                effectiveValue: "\"Welcome!\"",
                defaultValue: "\"Hello\"",
                mode: .info,
                hasOverride: false
            )
            FlagRowView(
                key: "features/max_items",
                displayName: "Max Items",
                type: .integer,
                effectiveValue: "25",
                defaultValue: "20",
                mode: .info,
                hasOverride: false
            )
            FlagRowView(
                key: "store/price_multiplier",
                displayName: "Price Multiplier",
                type: .double,
                effectiveValue: "1.50",
                defaultValue: "1.00",
                mode: .info,
                hasOverride: false
            )
            FlagRowView(
                key: "store/promo_end_date",
                displayName: "Promo End Date",
                type: .date,
                effectiveValue: "2025-01-15T10:00:00Z",
                defaultValue: "2024-12-31T23:59:59Z",
                mode: .info,
                hasOverride: false
            )
            FlagRowView(
                key: "layout/home_sections",
                displayName: "Home Sections",
                type: .json,
                effectiveValue: "{\"sections\":[\"featured\",\"recent\"]}",
                defaultValue: "{\"sections\":[\"featured\"]}",
                mode: .info,
                hasOverride: false
            )
        }

        Section("Info Mode — With Override") {
            FlagRowView(
                key: "features/max_items",
                displayName: "Max Items",
                type: .integer,
                effectiveValue: "60",
                defaultValue: "20",
                mode: .info,
                hasOverride: true
            )
        }

        Section("Debug Mode — Evaluated") {
            FlagRowView(
                key: "store/use_new_paywall_design",
                displayName: "Use New Paywall Design",
                type: .boolean,
                effectiveValue: "false",
                defaultValue: "false",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
            FlagRowView(
                key: "ui/welcome_message",
                displayName: "Welcome Message",
                type: .string,
                effectiveValue: "\"Hello World\"",
                defaultValue: "\"Hello\"",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
            FlagRowView(
                key: "features/max_items",
                displayName: "Max Items",
                type: .integer,
                effectiveValue: "25",
                defaultValue: "20",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
            FlagRowView(
                key: "store/price_multiplier",
                displayName: "Price Multiplier",
                type: .double,
                effectiveValue: "2.00",
                defaultValue: "1.00",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
            FlagRowView(
                key: "store/promo_end_date",
                displayName: "Promo End Date",
                type: .date,
                effectiveValue: "2025-06-30T23:59:59Z",
                defaultValue: "2024-12-31T23:59:59Z",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
            FlagRowView(
                key: "layout/home_sections",
                displayName: "Home Sections",
                type: .json,
                effectiveValue: "{\"sections\":[\"featured\",\"recent\"]}",
                defaultValue: "{\"sections\":[\"featured\"]}",
                mode: .debug,
                hasOverride: false,
                sourceBadgeTitle: "Evaluated",
                sourceBadgeColor: .green,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
        }

        Section("Debug Mode — With Override") {
            FlagRowView(
                key: "features/max_items",
                displayName: "Max Items",
                type: .integer,
                effectiveValue: "60",
                defaultValue: "20",
                mode: .debug,
                hasOverride: true,
                sourceBadgeTitle: "Override",
                sourceBadgeColor: .orange,
                onSetOverride: { _ in },
                onClearOverride: {}
            )
        }
    }
}
