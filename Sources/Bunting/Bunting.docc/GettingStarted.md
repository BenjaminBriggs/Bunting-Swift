# Getting Started with Bunting

Set up Bunting feature flags in your Apple app in minutes.

## Overview

This guide walks you through adding Bunting to your project, configuring it, and accessing your first feature flag.

## Add Bunting to Your Project

### Swift Package Manager

Add Bunting to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/bunting-sdk-swift", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter the Bunting repository URL
3. Add `Bunting` to your target

## Create Bootstrap Configuration

Create a file named `BuntingConfig.plist` in your app bundle with your CDN configuration
(ensure **Target Membership** is checked in Xcode):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>endpoint_url</key>
    <string>https://your-cdn.com/config.json</string>
    <key>public_keys</key>
    <array>
        <dict>
            <key>kid</key>
            <string>key-2024-01</string>
            <key>pem</key>
            <string>-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
-----END PUBLIC KEY-----</string>
        </dict>
    </array>
    <key>fetch_policy</key>
    <dict>
        <key>min_interval_seconds</key>
        <integer>300</integer>
        <key>hard_ttl_days</key>
        <integer>7</integer>
    </dict>
</dict>
</plist>
```

## Configure Bunting

Configure Bunting early in your app lifecycle (e.g., in your `@main` App struct):

```swift
import Bunting
import SwiftUI

@main
struct MyApp: App {
    init() {
        do {
            try Bunting.configure(environment: .production)
        } catch {
            print("Failed to configure Bunting: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Environment Selection

Choose the appropriate environment based on your build configuration:

```swift
#if DEBUG
    try Bunting.configure(environment: .development)
#else
    try Bunting.configure(environment: .production)
#endif
```

## Access Your First Flag

Access flags using type-safe methods:

```swift
import Bunting

struct ContentView: View {
    var body: some View {
        VStack {
            // Boolean flag
            if Bunting.shared.bool("feature/new_design", default: false) {
                NewDesignView()
            } else {
                LegacyDesignView()
            }
            
            // String flag
            let greeting = Bunting.shared.string("ui/greeting", default: "Hello!")
            Text(greeting)
            
            // Integer flag
            let limit = Bunting.shared.int("limits/max_items", default: 10)
            Text("Showing \(limit) items")
        }
    }
}
```

## Use Codegen for Type Safety

For even better type safety, use the Bunting codegen plugin. Add a seed configuration to your project, and the plugin will generate strongly-typed accessors:

```swift
// Instead of string keys:
Bunting.shared.bool("feature/new_design", default: false)

// Use generated accessors:
Bunting.shared.feature.newDesign
```

See the codegen plugin documentation for setup instructions.

## Enable Debug UI (Development Only)

During development, use the built-in debug UI to test flag values:

```swift
#if DEBUG
import Bunting

struct ContentView: View {
    @State private var showingDebugPanel = false
    
    var body: some View {
        NavigationStack {
            YourMainView()
                .toolbar {
                    ToolbarItem {
                        Button("Flags") {
                            showingDebugPanel = true
                        }
                    }
                }
                .sheet(isPresented: $showingDebugPanel) {
                    NavigationStack {
                        BuntingDebugView()
                    }
                }
        }
    }
}
#endif
```

## Next Steps

- Learn about <doc:UnderstandingVariants> for conditional logic
- Explore <doc:ABTesting> for running experiments
- Understand <doc:GradualRollouts> for safe feature deployment
- Review ``Bunting`` for the complete API reference

## Common Patterns

### Custom Attributes

Provide custom attribute resolution for dynamic conditions:

```swift
try Bunting.configure(
    environment: .production,
    customAttributes: { attribute in
        switch attribute {
        case "pro_user":
            return UserDefaults.standard.bool(forKey: "isPro")
        case "beta_tester":
            return UserDefaults.standard.bool(forKey: "isBeta")
        default:
            return false
        }
    }
)
```

### SwiftUI Integration

Use Bunting with SwiftUI's environment:

```swift
struct ContentView: View {
    @Environment(\.bunting) private var bunting
    
    var body: some View {
        if bunting.bool("feature/new_ui", default: false) {
            NewUIView()
        }
    }
}
```

### Testing with Overrides

Override flag values during testing:

```swift
// In your test setup
Bunting.shared.setOverride("feature/new_design", value: true)

// Run your tests

// Clean up
Bunting.shared.clearAllOverrides()
```
