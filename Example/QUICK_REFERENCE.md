# Bunting SDK - Quick Reference

A cheat sheet for common Bunting SDK operations.

## 🚀 Setup

```swift
import Bunting

// In app init
try? Bunting.configure(environment: .production)
```

## 📖 Reading Flags

```swift
let bunting = await Bunting.shared

// Boolean
let enabled = await bunting.bool("feature/enabled", default: false)

// String
let message = await bunting.string("ui/message", default: "Hello")

// Integer
let maxSize = await bunting.int("limits/size", default: 100)

// Double
let discount = await bunting.double("pricing/discount", default: 0.0)

// Date
let deadline = await bunting.date("events/deadline", default: Date())

// JSON
if let data = await bunting.jsonData("config/settings") {
    let settings = try? JSONDecoder().decode(Settings.self, from: data)
}
```

## 🔄 Refresh Configuration

```swift
await Bunting.shared.refresh()
```

## ℹ️ Configuration Info

```swift
let version = await bunting.configVersion        // "2025-01-15.1"
let published = await bunting.publishedAt        // Date
let verified = await bunting.signatureVerified   // true/false
let deviceID = await bunting.localID             // UUID
```

## 🧪 Testing with Overrides

```swift
// Set override
await bunting.setOverride("feature/enabled", value: true)

// Clear specific override
await bunting.clearOverride("feature/enabled")

// Clear all
await bunting.clearAllOverrides()
```

## 🔑 Identity Management

```swift
// Get current ID
let id = await bunting.localID

// Reset (generates new UUID)
try await bunting.resetIdentity()
```

## ⚙️ Advanced Configuration

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

## 📝 Flag Key Naming

Use namespaces with forward slashes:

```
✅ Good:
  - feature/new_ui
  - pricing/discount_percentage
  - limits/max_upload_size
  - ui/theme_color

❌ Avoid:
  - newUI
  - DiscountPercentage
  - MAX_UPLOAD_SIZE
```

## 🎯 SwiftUI Integration

```swift
struct MyView: View {
    @State private var enabled = false
    
    var body: some View {
        Toggle("Feature", isOn: $enabled)
            .task {
                enabled = await Bunting.shared.bool("feature/enabled", default: false)
            }
    }
}
```

## 🔍 Debugging Tips

### Check Configuration Status

```swift
let bunting = await Bunting.shared
print("Version:", await bunting.configVersion ?? "Not loaded")
print("Verified:", await bunting.signatureVerified)
```

### Test Different Values

Use the Debug Panel in the example app or:

```swift
#if DEBUG
await bunting.setOverride("feature/enabled", value: true)
#endif
```

### Force Refresh

```swift
await bunting.refresh()
// Respects min_interval_seconds from BuntingConfig.plist
```

## ⚠️ Common Mistakes

### ❌ Forgetting `await`

```swift
// Wrong
let enabled = Bunting.shared.bool("feature/enabled", default: false)

// Correct
let enabled = await Bunting.shared.bool("feature/enabled", default: false)
```

### ❌ Not Providing Defaults

```swift
// Wrong - won't compile
let message = await bunting.string("ui/message")

// Correct
let message = await bunting.string("ui/message", default: "Hello")
```

### ❌ Missing BuntingConfig.plist

```
Error: BuntingConfig.plist not found

Fix: Add to project and ensure Target Membership is checked
```

### ❌ Synchronous Access

```swift
// Wrong - Bunting uses actors and async/await
func getFlag() -> Bool {
    return Bunting.shared.bool("feature/enabled", default: false)
}

// Correct
func getFlag() async -> Bool {
    return await Bunting.shared.bool("feature/enabled", default: false)
}
```

## 🏗️ BuntingConfig.plist Structure

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
        <integer>60</integer>
        <key>hard_ttl_days</key>
        <integer>7</integer>
    </dict>
</dict>
</plist>
```

## 📊 Environments

```swift
// Development (typically local/dev backend)
try? Bunting.configure(environment: .development)

// Staging (pre-production testing)
try? Bunting.configure(environment: .staging)

// Production (live users)
try? Bunting.configure(environment: .production)
```

Each environment has its own flag configuration in the backend.

## 🔐 Security

### Signature Verification

- Configuration must be signed with JWS (RS256)
- Public key in BuntingConfig.plist verifies signature
- If verification fails, cached config is used
- If no cache, code defaults are used

### Key Rotation

Support multiple keys for gradual rotation:

```xml
<key>public_keys</key>
<array>
    <dict>
        <key>kid</key>
        <string>key-2025-01</string>
        <key>pem</key>
        <string>...new key...</string>
    </dict>
    <dict>
        <key>kid</key>
        <string>key-2024-12</string>
        <key>pem</key>
        <string>...old key...</string>
    </dict>
</array>
```

## 📱 Platform Support

- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+

## 🎓 Learning Path

1. **Start**: Read the [Example README](README.md)
2. **Explore**: Run the example app and try the Debug Panel
3. **Integrate**: Add to your own app
4. **Customize**: Add your own flags and targeting rules
5. **Deploy**: Set up backend and publish configuration

## 📚 More Resources

- [Main SDK README](../README.md)
- [Full Documentation](../../../docs/)
- [Example App](README.md)
- [API Reference](../Sources/Bunting/)

---

**Quick Links:**
- Configuration not loading? Check [README#Troubleshooting](README.md#troubleshooting)
- Adding custom flags? See [README#Modifying-the-Example](README.md#modifying-the-example)
- Backend setup? See main project docs
