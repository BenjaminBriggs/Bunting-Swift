# Bunting Swift SDK

A self-hosted, open-source feature flag and rollout system for Apple platforms.

## Features

- **Offline-First**: Local evaluation with signed artifact verification
- **Strongly-Typed**: Generated accessors for type-safe flag access
- **Secure**: JWS signature verification with RS256
- **Privacy-Preserving**: Deterministic bucketing with device-local UUID
- **Multi-Environment**: Support for development, staging, and production
- **Debug UI**: Built-in override and inspection tools

## Requirements

- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- Swift 6.0+

## Installation

### Swift Package Manager

Add Bunting to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/bunting-sdk-swift.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File > Add Package Dependencies
2. Enter the repository URL
3. Select your target and add the package

## Example App

A complete iOS example application is available in the `Examples/` directory demonstrating:

- Basic integration and configuration
- Reading different flag types
- Debug panel with overrides
- Configuration inspection
- Identity management

**Quick start**: See [Examples/QUICKSTART.md](Examples/QUICKSTART.md) for step-by-step setup instructions.

## Quick Start

### 1. Add Bootstrap Configuration

Create `BuntingConfig.plist` in your app bundle:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>endpoint_url</key>
    <string>https://cdn.example.com/flags/my-app/config.json</string>
    <key>public_keys</key>
    <array>
        <dict>
            <key>kid</key>
            <string>key-2025-01</string>
            <key>pem</key>
            <string>-----BEGIN PUBLIC KEY-----
... your public key ...
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

### 2. Configure Bunting

In your app's entry point:

```swift
import Bunting

@main
struct MyApp: App {
    init() {
        try? Bunting.configure(
            environment: .production
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 3. Use Flags

```swift
import Bunting

struct ContentView: View {
    var body: some View {
        VStack {
            if await Bunting.shared.bool("store/use_new_paywall_design", default: false) {
                NewPaywallView()
            } else {
                OldPaywallView()
            }
        }
    }
}
```

## Flag Types

Bunting supports six flag types:

```swift
// Boolean
let enabled = await Bunting.shared.bool("feature/enabled", default: false)

// String
let message = await Bunting.shared.string("ui/welcome_message", default: "Hello")

// Integer
let maxSize = await Bunting.shared.int("features/max_upload_size", default: 25)

// Double
let discount = await Bunting.shared.double("features/discount", default: 0.10)

// Date
let deadline = await Bunting.shared.date("features/deadline", default: Date())

// JSON
if let data = await Bunting.shared.jsonData("layout/home_sections") {
    let sections = try? JSONDecoder().decode(HomeSections.self, from: data)
}
```

## Configuration

### Environment Selection

Choose the environment at configuration time:

```swift
#if DEBUG
try? Bunting.configure(environment: .development)
#else
try? Bunting.configure(environment: .production)
#endif
```

### Custom Attributes

Provide custom attribute resolvers for advanced targeting:

```swift
try? Bunting.configure(
    environment: .production,
    customAttributes: { attribute in
        switch attribute {
        case "is_premium":
            return UserDefaults.standard.bool(forKey: "isPremium")
        case "has_active_subscription":
            return SubscriptionManager.shared.isActive
        default:
            return false
        }
    }
)
```

### Keychain Access Group

For sharing identity across apps:

```swift
try? Bunting.configure(
    environment: .production,
    keychainAccessGroup: "group.com.example.shared"
)
```

## Manual Refresh

Trigger a config refresh manually:

```swift
await Bunting.shared.refresh()
```

## Debug Overrides

Set local overrides for testing:

```swift
// Set override
Bunting.shared.setOverride("store/use_new_paywall_design", value: true)

// Clear specific override
Bunting.shared.clearOverride("store/use_new_paywall_design")

// Clear all overrides
Bunting.shared.clearAllOverrides()
```

## Identity Management

Reset the local identity (generates new UUID):

```swift
try await Bunting.shared.resetIdentity()
```

## Architecture

### Components

- **ConfigStore**: Manages fetching, verification, and caching of configuration
- **Identity**: Keychain-backed persistent UUID for deterministic bucketing
- **Evaluator**: Condition and flag evaluation engine
- **OverridesStore**: Local flag override management

### Data Flow

1. **Bootstrap**: Load `BuntingConfig.plist` with endpoint and public keys
2. **Fetch**: Download signed configuration from CDN with ETag caching
3. **Verify**: Validate JWS signature using embedded public keys
4. **Cache**: Persist verified config to Application Support
5. **Evaluate**: Resolve flags locally using conditions, tests, and rollouts
6. **Override**: Apply local overrides for debugging

### Evaluation Order

For each flag in an environment:

1. Check local overrides (highest priority)
2. Iterate variants by ascending `order`:
   - **Conditional**: Evaluate conditions → return value if all pass
   - **Test**: Check preconditions → bucket user → return group value
   - **Rollout**: Check preconditions → bucket user → return value if ≤ percentage
3. Return default value (fallback)

### Bucketing Algorithm

Deterministic bucketing for tests and rollouts:

1. Concatenate `salt:localID` (e.g., `"unique-salt:550E8400-..."`)
2. Compute SHA-256 hash of UTF-8 bytes
3. Take first 8 bytes as unsigned big-endian UInt64
4. Return `(value % 100) + 1` → bucket 1-100

## Example Configuration

See `Examples/sample-config.json` for a complete configuration example demonstrating:

- Multiple flag types
- Cohort definitions
- Conditional variants
- Test and rollout configurations
- Environment-specific overrides

## Testing

Run unit tests:

```bash
cd bunting-sdk-swift
swift test
```

Tests cover:
- Deterministic bucketing algorithm
- Condition evaluation (platform, version, region, locale, cohorts)
- Flag resolution with variant ordering
- Keychain identity persistence

## Security

### Signature Verification

All configurations must be signed with RS256:

1. Server signs `config.json` with private key
2. Signature included in `x-bunting-signature` header
3. SDK verifies using embedded public key(s)
4. On failure, falls back to cached config

### Key Rotation

Multiple public keys supported via `kid` (key ID):

```xml
<key>public_keys</key>
<array>
    <dict>
        <key>kid</key>
        <string>key-2025-01</string>
        <key>pem</key>
        <string>... public key ...</string>
    </dict>
    <dict>
        <key>kid</key>
        <string>key-2024-12</string>
        <key>pem</key>
        <string>... old public key ...</string>
    </dict>
</array>
```

### Privacy

- Local ID stored in iCloud Keychain (survives reinstall)
- Never transmitted to backend
- Used only for deterministic bucketing
- Can be reset by user

## Performance

- **Flag lookup**: < 2µs (memoized), < 100µs (cold)
- **Config parse**: < 25ms for 5K flags
- **Memory**: < 5MB typical

## Limitations (v1)

- No real-time updates (periodic polling only)
- No built-in analytics or exposure tracking
- No server-side evaluation
- Apple platforms only

## Contributing

This is part of the Bunting project. See the main repository for contribution guidelines.

## License

[Your License]

## Support

For issues and questions, please use the main Bunting repository.
