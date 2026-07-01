# Bunting SDK — Quick Reference

A cheat sheet for common Bunting SDK operations.

## Setup

```swift
import Bunting

// In app init — call once before accessing any flags
try? Bunting.configure(environment: .production)
```

## Reading Flags

Flag access is synchronous and safe to call from any `@MainActor` context (e.g., SwiftUI body):

```swift
// Boolean
let enabled = Bunting.shared.bool("feature/enabled", default: false)

// String
let message = Bunting.shared.string("ui/message", default: "Hello")

// Integer
let maxSize = Bunting.shared.int("limits/size", default: 100)

// Double
let discount = Bunting.shared.double("pricing/discount", default: 0.0)

// Date
let deadline = Bunting.shared.date("events/deadline", default: Date())

// JSON
if let data = Bunting.shared.jsonData("config/settings") {
    let settings = try? JSONDecoder().decode(Settings.self, from: data)
}
```

## Refresh Configuration

```swift
// Async; respects min_interval_seconds rate limiting
await Bunting.shared.refresh()
```

## Configuration Info

```swift
let version  = Bunting.shared.configVersion      // "2025-01-15.1"
let published = Bunting.shared.publishedAt        // Date?
let verified  = Bunting.shared.signatureVerified  // true only when JWS verified in this process
let source   = Bunting.shared.configSource        // ConfigSource? (.fetched/.cache/.seed)
let deviceID  = Bunting.shared.localID            // UUID
```

## Testing with Overrides

```swift
// Set override (persisted to UserDefaults)
Bunting.shared.setOverride("feature/enabled", value: true)

// Clear specific override
Bunting.shared.clearOverride("feature/enabled")

// Clear all
Bunting.shared.clearAllOverrides()
```

## Identity Management

```swift
// Current device ID (used for deterministic bucketing)
let id = Bunting.shared.localID

// Reset — generates new UUID, re-randomises test/rollout assignment
try await Bunting.shared.resetIdentity()
```

## Advanced Configuration

### Custom Attributes

```swift
try? Bunting.configure(
    environment: .production,
    customAttributes: { attribute in
        switch attribute {
        case "is_premium":
            return UserDefaults.standard.bool(forKey: "isPremium")
        default:
            return false
        }
    }
)
```

### Shared Keychain

```swift
try? Bunting.configure(
    environment: .production,
    keychainAccessGroup: "group.com.yourcompany.shared"
)
```

## Flag Key Naming

Use namespaces with forward slashes:

```
Good:
  feature/new_ui
  pricing/discount_percentage
  limits/max_upload_size

Avoid:
  newUI
  DiscountPercentage
  MAX_UPLOAD_SIZE
```

## SwiftUI Integration

`Bunting` is `@Observable`, so reading its properties in a SwiftUI body automatically
tracks changes:

```swift
struct MyView: View {
    var body: some View {
        if Bunting.shared.bool("feature/enabled", default: false) {
            EnabledView()
        }
    }
}
```

Or via the environment key:

```swift
struct MyView: View {
    @Environment(\.bunting) private var bunting

    var body: some View {
        if bunting.bool("feature/enabled", default: false) {
            EnabledView()
        }
    }
}
```

## Debugging Tips

### Check Configuration Status

```swift
print("Version:", Bunting.shared.configVersion ?? "Not loaded")
print("Verified:", Bunting.shared.signatureVerified)  // false for seed and while nothing is loaded
print("Source:", Bunting.shared.configSource?.rawValue ?? "none")
```

### Test Different Values

Use `BuntingDebugView` (see example app), or set overrides directly:

```swift
#if DEBUG
Bunting.shared.setOverride("feature/enabled", value: true)
#endif
```

### Force Refresh

```swift
await Bunting.shared.refresh()
// Respects min_interval_seconds from BuntingConfig.plist
```

## Common Mistakes

### Calling configure() after accessing shared

```swift
// Wrong — shared is auto-created with defaults before configure() runs
let value = Bunting.shared.bool("feature/x", default: false)
try? Bunting.configure(environment: .development)

// Correct — configure first
try? Bunting.configure(environment: .development)
let value = Bunting.shared.bool("feature/x", default: false)
```

### Not providing a default value

```swift
// Won't compile
let message = Bunting.shared.string("ui/message")

// Correct
let message = Bunting.shared.string("ui/message", default: "Hello")
```

### Missing BuntingConfig.plist target membership

```
Error thrown from configure(): BuntingError.invalidConfiguration

Fix: Select BuntingConfig.plist in Xcode → File Inspector → check Target Membership
```

## BuntingConfig.plist Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>endpoint_url</key>
    <string>https://cdn.example.com/your-app/config.json</string>

    <key>public_keys</key>
    <array>
        <dict>
            <key>kid</key>
            <string>key-2025-01</string>
            <key>pem</key>
            <string>-----BEGIN PUBLIC KEY-----
...your public key...
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

## Environments

```swift
try? Bunting.configure(environment: .development)  // local/dev backend
try? Bunting.configure(environment: .beta)      // pre-production
try? Bunting.configure(environment: .production)   // live users
```

Each environment has its own default values and variants in the config artifact.

## Security

- Configuration signed with JWS (RS256); public key in `BuntingConfig.plist` verifies it
- Signature delivered via `x-bunting-signature` response header or `<endpoint>.sig` file (`.sig` is the fallback)
- The persisted JWS is re-verified over cached bytes on every cache load
- `signatureVerified` is `true` only when the JWS was verified in this process; `false` for the bundled seed
- On verification failure, last-good cached config is used; on no cache, code defaults apply
- Multiple `public_keys` entries supported for zero-downtime key rotation

## Platform Support

- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- visionOS 2.0+

## More Resources

- [Main SDK README](../README.md)
- [Architecture](architecture.md)
- [Plugins reference](plugins.md)
- [API reference — DocC](../Sources/Bunting/Bunting.docc/)
