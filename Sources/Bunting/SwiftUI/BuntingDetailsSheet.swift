import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct BuntingDetailsSheet: View {
    let environment: BuntingEnvironment
    let configVersion: String?
    let publishedAt: Date?
    let signatureVerified: Bool
    let localID: String
    let lastFetchTime: Date?
    let etag: String?
    let showResetIdentity: Bool
    let onResetIdentity: (() -> Void)?
    let onRefresh: (() async -> Void)?
    @State private var isRefreshing = false
    let onChangeEnvironment: ((BuntingEnvironment) -> Void)?
    @State private var selectedEnvironment: BuntingEnvironment
    
    @State private var showResetConfirmation = false
    
    public init(
        environment: BuntingEnvironment,
        configVersion: String?,
        publishedAt: Date?,
        signatureVerified: Bool,
        localID: String,
        lastFetchTime: Date?,
        etag: String?,
        showResetIdentity: Bool = false,
        onResetIdentity: (() -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        onChangeEnvironment: ((BuntingEnvironment) -> Void)? = nil
    ) {
        self.environment = environment
        self.configVersion = configVersion
        self.publishedAt = publishedAt
        self.signatureVerified = signatureVerified
        self.localID = localID
        self.lastFetchTime = lastFetchTime
        self.etag = etag
        self.showResetIdentity = showResetIdentity
        self.onResetIdentity = onResetIdentity
        self.onRefresh = onRefresh
        self.onChangeEnvironment = onChangeEnvironment
        _selectedEnvironment = State(initialValue: environment)
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Configuration") {
                    if let onChangeEnvironment {
                        Picker("Environment", selection: $selectedEnvironment) {
                            Text("Development").tag(BuntingEnvironment.development)
                            Text("Staging").tag(BuntingEnvironment.staging)
                            Text("Production").tag(BuntingEnvironment.production)
                        }
                        #if os(iOS)
                        .pickerStyle(.segmented)
                        #endif
                        .onChange(of: selectedEnvironment) { newValue in
                            onChangeEnvironment(newValue)
                        }
                    } else {
                        LabeledContent("Environment", value: selectedEnvironment.rawValue.capitalized)
                    }
                }
                
                Section("Status") {
                    if let version = configVersion {
                        LabeledContent("Version", value: version)
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
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                Text("Verified")
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text("Not Verified")
                            }
                        }
                        .font(.subheadline)
                    }
                }
                
                if etag != nil || lastFetchTime != nil {
                    Section {
                        if let last = lastFetchTime {
                            LabeledContent("Last Fetch") {
                                Text(last, style: .relative)
                            }
                        }
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
                        if etag != nil {
                            Text("ETag is used for efficient caching with conditional GET.")
                        }
                    }
                }
                
                Section {
                    LabeledContent("Local ID") {
                        Text(localID)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    
                    if showResetIdentity, let onResetIdentity {
                        Button(role: .destructive) {
                            showResetConfirmation.toggle()
                        } label: {
                            Label("Reset Identity", systemImage: "arrow.clockwise")
                        }
                        .confirmationDialog(
                            "Reset Identity?",
                            isPresented: $showResetConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Reset", role: .destructive) {
                                onResetIdentity()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will generate a new UUID and may change cohort assignments and rollout buckets.")
                        }
                    }
                } header: {
                    Text("Device Identity")
                } footer: {
                    Text("The local ID is stored in the keychain and used for deterministic bucketing.")
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onRefresh {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                isRefreshing = true
                                await onRefresh()
                                isRefreshing = false
                            }
                        } label: {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshing)
                    }
                }
            }
        }
    }
}

#Preview("Details Sheet Example") {
    BuntingDetailsSheet(
        environment: .production,
        configVersion: "2025-01-15.1",
        publishedAt: ISO8601DateFormatter().date(from: "2025-01-15T10:00:00Z"),
        signatureVerified: true,
        localID: "8F6B4D3C-2A1B-4E0F-98C1-1234567890AB",
        lastFetchTime: Date(timeIntervalSinceNow: -3600),
        etag: "W/\"abcd1234\"",
        showResetIdentity: true,
        onResetIdentity: {}
    )
}

#Preview("Unverified — Minimal Data") {
    BuntingDetailsSheet(
        environment: .staging,
        configVersion: nil,
        publishedAt: nil,
        signatureVerified: false,
        localID: "D1C2B3A4-0000-1111-2222-333344445555",
        lastFetchTime: nil,
        etag: nil,
        showResetIdentity: false
    )
}

#Preview("With ETag, No Last Fetch") {
    BuntingDetailsSheet(
        environment: .development,
        configVersion: "2025-02-10.3",
        publishedAt: ISO8601DateFormatter().date(from: "2025-02-10T08:30:00Z"),
        signatureVerified: true,
        localID: "11111111-2222-3333-4444-555555555555",
        lastFetchTime: nil,
        etag: "\"etag-987654\"",
        showResetIdentity: true,
        onResetIdentity: {}
    )
}

#Preview("Long Values") {
    BuntingDetailsSheet(
        environment: .production,
        configVersion: "2025-03-01.12-extra-long-version-identifier",
        publishedAt: ISO8601DateFormatter().date(from: "2025-03-01T12:00:00Z"),
        signatureVerified: true,
        localID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEFFFFFFFF",
        lastFetchTime: Date(timeIntervalSinceNow: -86400),
        etag: "W/\"very-long-etag-value-1234567890abcdefghijklmnopqrstuvwxyz\"",
        showResetIdentity: false
    )
}
