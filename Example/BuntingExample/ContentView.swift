//
//  ContentView.swift
//  BuntingExample
//
//  Created by Benjamin Briggs on 24/10/2025.
//

import Bunting
import SwiftUI

struct ContentView: View {
    @BuntingFlag(\.store.useNewPaywallDesign)
    private var typedUseNewDesign: Bool
    
    @BuntingFlag(\.features.maxItems)
    private var typedMaxItems: Int
    
    @BuntingFlag(\.ui.themeColor)
    private var typedThemeColor: String

    // MARK: - State Properties
    // These properties hold the current values of our feature flags
    // They're updated when the view appears and when we manually refresh

    @State private var useNewDesign = false
    @State private var welcomeMessage = "Loading..."
    @State private var maxUploadSize = 0
    @State private var themeColor = "#007AFF"
    @State private var discountPercentage = 0.0

    // Configuration metadata
    @State private var configVersion: String?
    @State private var publishedAt: Date?
    @State private var isVerified = false

    // UI state
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                     HStack {
                         Text("Typed: New Paywall Design")
                         Spacer()
                         Image(
                             systemName: typedUseNewDesign
                                 ? "checkmark.circle.fill" : "xmark.circle.fill"
                         )
                         .foregroundStyle(typedUseNewDesign ? .green : .red)
                     }
                    
                     HStack {
                         Text("Typed: Max Items")
                         Spacer()
                         Text("\(typedMaxItems)")
                             .foregroundStyle(.secondary)
                     }
                    
                     HStack {
                         Text("Typed: Theme Color")
                         Spacer()
                         Text(typedThemeColor)
                             .foregroundStyle(.secondary)
                     }

                    // Boolean flag example
                    // Shows a checkmark or X mark based on the flag value
                    HStack {
                        Text("New Paywall Design")
                        Spacer()
                        if useNewDesign {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    // String flag example
                    HStack {
                        Text("Welcome Message")
                        Spacer()
                        Text(welcomeMessage)
                            .foregroundStyle(.secondary)
                    }

                    // Integer flag example
                    HStack {
                        Text("Max Upload Size")
                        Spacer()
                        Text("\(maxUploadSize) MB")
                            .foregroundStyle(.secondary)
                    }

                    // String flag example (color)
                    HStack {
                        Text("Theme Color")
                        Spacer()
                        HStack(spacing: 4) {
                            Text(themeColor)
                                .foregroundStyle(.secondary)
                            // Show a color preview circle
                            if let color = Color(hex: themeColor) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }

                    // Double flag example (percentage)
                    HStack {
                        Text("Discount")
                        Spacer()
                        Text("\(Int(discountPercentage * 100))%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Feature Flags")
                } footer: {
                    Text(
                        "These values are loaded from your Bunting configuration and evaluated locally on the device."
                    )
                }

                // MARK: - Configuration Info Section
                // Shows metadata about the current configuration

                Section {
                    // Show all flags and their current values using generated list
                    let all = BuntingPaths(bunting: Bunting.shared).allFlags
                    ForEach(all, id: \.key) { item in
                        HStack {
                            Text(item.key)
                            Spacer()
                            Text(item.makeString(Bunting.shared))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("All Flags (current values)")
                }

                Section {
                    if let version = configVersion {
                        LabeledContent("Config Version", value: version)
                    } else {
                        HStack {
                            Text("Config Version")
                            Spacer()
                            Text("Not loaded")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let published = publishedAt {
                        LabeledContent("Published") {
                            Text(published, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Signature") {
                        HStack {
                            if isVerified {
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
                    Text("Configuration Info")
                } footer: {
                    Text(
                        "Signature verification ensures the configuration hasn't been tampered with."
                    )
                }

                // MARK: - Actions Section

                Section {
                    // Manual refresh button
                    // Triggers a fetch from the backend to get the latest configuration
                    Button {
                        Task {
                            await refreshConfiguration()
                        }
                    } label: {
                        HStack {
                            if isRefreshing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Refresh Configuration")
                        }
                    }
                    .disabled(isRefreshing)

                    // Navigate to debug panels
                    NavigationLink("Info View") {
                        BuntingInfoView()
                    }

                    NavigationLink("Debug View") {
                        BuntingDebugView()
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text(
                        "Use the Debug Panel to test flag overrides without changing your backend configuration."
                    )
                }
            }
            .navigationTitle("Bunting Example")
            // Load flags when the view first appears
            .task {
                await loadFlags()
            }
        }
    }

    // MARK: - Methods

    /// Loads all flag values from Bunting
    /// This demonstrates the different accessor methods for each flag type
    private func loadFlags() async {
        // Get a reference to the shared Bunting instance
        let bunting = Bunting.shared

        // MARK: Boolean Flags
        // Use the bool() method with a default value
        // If the flag doesn't exist or can't be evaluated, the default is returned
        useNewDesign = bunting.bool(
            "store/use_new_paywall_design",
            default: false
        )

        // MARK: String Flags
        // Use the string() method
        welcomeMessage = bunting.string(
            "ui/welcome_message",
            default: "Welcome!"
        )

        themeColor = bunting.string(
            "ui/theme_color",
            default: "#007AFF"
        )

        // MARK: Integer Flags
        // Use the int() method for whole numbers
        maxUploadSize = bunting.int(
            "features/max_upload_size",
            default: 25
        )

        // MARK: Double Flags
        // Use the double() method for decimal numbers
        discountPercentage = bunting.double(
            "features/discount_percentage",
            default: 0.10
        )

        // MARK: Configuration Metadata
        // You can also access information about the configuration itself
        configVersion = bunting.configVersion
        publishedAt = bunting.publishedAt
        isVerified = bunting.signatureVerified

        // MARK: Other Flag Types

        // For Date flags:
        // let deadline = await bunting.date("events/deadline", default: Date())

        // For JSON flags:
        // if let data = await bunting.jsonData("layout/home_sections") {
        //     let decoder = JSONDecoder()
        //     let sections = try? decoder.decode(HomeSections.self, from: data)
        // }
    }

    /// Manually refreshes the configuration from the backend
    /// This respects rate limiting configured in BuntingConfig.plist
    private func refreshConfiguration() async {
        isRefreshing = true

        let bunting = Bunting.shared

        // Trigger a refresh from the backend
        // This will:
        // 1. Check if enough time has passed since last fetch (rate limiting)
        // 2. Make a conditional GET request with ETag
        // 3. Verify the signature if new data is received
        // 4. Update the cached configuration
        await bunting.refresh()

        // Reload flag values to reflect any changes
        await loadFlags()

        isRefreshing = false
    }
}

// MARK: - Helper Extensions

/// Extension to create SwiftUI Color from hex string
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else {
            return nil
        }

        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
