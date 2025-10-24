//
//  DebugView.swift
//  BuntingExample
//
//  Created by Benjamin Briggs on 24/10/2025.
//

import Bunting
import SwiftUI

/// Debug panel for testing and troubleshooting Bunting configuration
/// This view provides tools for:
/// - Inspecting configuration status and metadata
/// - Viewing and resetting the device's persistent identity
/// - Testing flag behavior with local overrides
struct DebugView: View {
    // MARK: - State Properties

    // Configuration metadata
    @State private var configVersion: String?
    @State private var publishedAt: Date?
    @State private var signatureVerified = false
    @State private var localID: String = ""
    
    var maxItems = Bunting.shared.features.maxItems
    
    // Override states for testing
    // Each flag can have a local override that takes precedence over the backend value
    @State private var paywallOverride: Bool?
    @State private var uploadSizeOverride: Int?

    // UI state
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            // MARK: - Configuration Status Section
            // Shows the current state of the loaded configuration

            Section {
                // Config version from the backend
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

                // When the configuration was published
                if let published = publishedAt {
                    LabeledContent("Published At") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(published, style: .relative)
                            Text(published, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Signature verification status
                // Green checkmark = verified, orange warning = not verified
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
                Text("Configuration Status")
            } footer: {
                Text(
                    "Configuration is fetched from your backend, verified with JWS signature, and cached locally."
                )
            }

            // MARK: - Identity Section
            // Shows and manages the persistent device UUID used for bucketing

            Section {
                // Display the local ID (UUID)
                // This is stored in the keychain and persists across app reinstalls
                LabeledContent("Local ID") {
                    Text(localID)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)  // Allow copying
                }

                // Reset identity button
                // Generates a new UUID, which will cause the user to be re-bucketed
                // Useful for testing different cohort assignments
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
                        "This will generate a new UUID and may change your cohort assignments and rollout bucket."
                    )
                }
            } header: {
                Text("Device Identity")
            } footer: {
                Text(
                    "The local ID is stored in the keychain and used for deterministic bucketing in tests and rollouts. Resetting it will generate a new UUID."
                )
            }

            // MARK: - Flag Overrides Section
            // Allows testing different flag values without changing the backend

            Section {
                // Boolean flag override example
                Toggle(
                    isOn: Binding(
                        get: { paywallOverride ?? false },
                        set: { newValue in
                            paywallOverride = newValue
                            Task {
                                await setFlagOverride(
                                    key: "store/use_new_paywall_design",
                                    value: newValue
                                )
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Paywall Design")
                        Text("store/use_new_paywall_design")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Integer flag override example with stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Upload Size")
                        Text("features/max_upload_size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Stepper(
                        value: Binding(
                            get: { uploadSizeOverride ?? 25 },
                            set: { newValue in
                                uploadSizeOverride = newValue
                                Task {
                                    await setFlagOverride(
                                        key: "features/max_upload_size",
                                        value: newValue
                                    )
                                }
                            }
                        ),
                        in: 10...100,
                        step: 5
                    ) {
                        Text("\(uploadSizeOverride ?? 25) MB")
                            .monospacedDigit()
                    }
                }

                // Clear all overrides button
                Button(role: .destructive) {
                    Task {
                        await clearAllOverrides()
                    }
                } label: {
                    Label("Clear All Overrides", systemImage: "trash")
                }
            } header: {
                Text("Flag Overrides")
            } footer: {
                Text(
                    "Overrides let you test different flag values locally. They take precedence over backend values and persist across app launches."
                )
            }

            // MARK: - Tips Section

            Section {
                Label {
                    Text("Overrides are stored in UserDefaults and persist across launches")
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }

                Label {
                    Text("Resetting identity helps test different rollout buckets")
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }

                Label {
                    Text("Changes to overrides take effect immediately")
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Tips")
            }
        }
        .navigationTitle("Debug Panel")
        .navigationBarTitleDisplayMode(.inline)
        // Load debug info when the view appears
        .task {
            await loadDebugInfo()
        }
    }

    // MARK: - Methods

    /// Loads configuration metadata and identity information
    private func loadDebugInfo() async {
        let bunting = Bunting.shared

        // Get configuration metadata
        configVersion = bunting.configVersion
        publishedAt = bunting.publishedAt
        signatureVerified = bunting.signatureVerified

        // Get the persistent local ID
        localID = bunting.localID.uuidString
    }

    /// Resets the device's persistent identity
    /// This generates a new UUID and invalidates any memoized flag values
    private func resetIdentity() async {
        let bunting = Bunting.shared

        // Reset the identity (generates new UUID)
        try? await bunting.resetIdentity()

        // Reload to show the new ID
        await loadDebugInfo()
    }

    /// Sets a local override for a specific flag
    /// The override takes precedence over the backend value until cleared
    private func setFlagOverride(key: String, value: Any) async {
        let bunting = Bunting.shared
        bunting.setOverride(key, value: value)
    }

    /// Clears all local overrides
    /// After clearing, flags will return to their backend-evaluated values
    private func clearAllOverrides() async {
        let bunting = Bunting.shared
        bunting.clearAllOverrides()

        // Reset UI state
        paywallOverride = nil
        uploadSizeOverride = nil
    }
}

#Preview {
    NavigationStack {
        DebugView()
    }
}
