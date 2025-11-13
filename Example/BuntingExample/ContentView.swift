//

import Bunting
import SwiftUI

struct ContentView: View {
    
    // MARK: - Remote Properties
    // These properties hold the current values of our feature flags
    // They're updated automatically when the flag changes.
    
    @BuntingFlag(\.store.useNewPaywallDesign)
    private var useNewDesign: Bool
    
    @BuntingFlag(\.features.maxItems)
    private var maxItems: Int
    
    @BuntingFlag(\.ui.themeColor)
    private var themeColor: String

    // MARK: - State Properties
    // These properties hold the current values of our feature flags
    // They're updated when the view appears and when we manually refresh

    @State private var viewModel = ViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                Section {
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
                        Text(viewModel.welcomeMessage)
                            .foregroundStyle(.secondary)
                    }

                    // Integer flag example
                    HStack {
                        Text("Max Upload Size")
                        Spacer()
                        Text("\(viewModel.maxUploadSize) MB")
                            .foregroundStyle(.secondary)
                    }

                    // String flag example (color)
                    HStack {
                        Text("Theme Color")
                        Spacer()
                        HStack(spacing: 4) {
                            Text(themeColor)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Double flag example (percentage)
                    HStack {
                        Text("Discount")
                        Spacer()
                        Text("\(Int(viewModel.discountPercentage * 100))%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Feature Flags")
                } footer: {
                    Text(
                        "These values are loaded from your Bunting configuration and evaluated locally on the device."
                    )
                }

                // MARK: - Actions Section

                Section {
                    // Manual refresh button
                    // Triggers a fetch from the backend to get the latest configuration
                    Button {
                        Task {
                            await viewModel.refreshConfiguration()
                        }
                    } label: {
                        HStack {
                            if viewModel.isRefreshing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Refresh Configuration")
                        }
                    }
                    .disabled(viewModel.isRefreshing)

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
                await viewModel.loadFlags()
            }
        }
    }
}

#Preview {
    ContentView()
}
