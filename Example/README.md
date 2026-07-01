# Bunting Example App

This is a complete iOS example application demonstrating how to integrate and use the Bunting SDK in a real-world app.

## 📱 What's Included

The example app demonstrates:

- **SDK Configuration** - Setting up Bunting on app launch
- **Flag Access** - Reading all flag types (bool, string, int, double, date, json)
- **Configuration Info** - Viewing version, publish date, and signature status
- **Manual Refresh** - Triggering config updates from the backend
- **Debug Panel** - Testing with local overrides without changing backend
- **Identity Management** - Viewing and resetting the device's persistent UUID

## 🏗️ Project Structure

```
BuntingExample/
├── BuntingExampleApp.swift    # App entry point with Bunting configuration
├── ContentView.swift           # Main view showing flag values
├── DebugView.swift             # Debug panel for testing
├── BuntingConfig.plist         # SDK configuration (endpoint, keys, policy)
└── Assets.xcassets/            # App assets
```

## 🚀 Getting Started

### 1. Open the Project

```bash
cd bunting-sdk-swift/Example
open BuntingExample.xcodeproj
```

### 2. Configure Your Backend (Optional)

The app will work without a backend (using defaults), but to test with real configuration:

1. **Set up Bunting Admin** (see main project documentation)
2. **Generate an RSA key pair**:
   ```bash
   # Generate private key
   openssl genrsa -out private.pem 2048
   
   # Generate public key
   openssl rsa -in private.pem -pubout -out public.pem
   ```

3. **Update `BuntingConfig.plist`**:
   - Change `endpoint_url` to your CDN URL
   - Replace the public key with your actual key from `public.pem`

4. **Publish Configuration** from your admin panel

### 3. Build and Run

1. Select a simulator or device
2. Press **⌘R** to build and run
3. The app will launch and display flag values

## 📖 Code Walkthrough

### BuntingExampleApp.swift

The app entry point shows minimal configuration:

```swift
import Bunting

init() {
    #if DEBUG
    try? Bunting.configure(environment: .development)
    #else
    try? Bunting.configure(environment: .production)
    #endif
}
```

**Key Points:**
- Configuration happens once on app launch
- Environment selection based on build configuration
- All flag access happens through `Bunting.shared`

### ContentView.swift

The main view demonstrates flag access patterns:

```swift
// Boolean flags
let enabled = bunting.bool("feature/enabled", default: false)

// String flags
let message = bunting.string("ui/message", default: "Hello")

// Integer flags
let size = bunting.int("limits/upload", default: 25)

// Double flags (percentages, decimals)
let discount = bunting.double("pricing/discount", default: 0.10)

// Date flags
let deadline = bunting.date("events/deadline", default: Date())

// JSON flags
if let data = bunting.jsonData("config/layout") {
    let config = try? JSONDecoder().decode(LayoutConfig.self, from: data)
}
```

**Key Points:**
- Flag accessors are synchronous (`@MainActor`) — no `await` needed; only `refresh()` and `resetIdentity()` are `async`
- Always provide a `default` value
- Use flag keys with namespaces (e.g., `"feature/enabled"`)
- Default values are used when flags don't exist or can't be evaluated

### DebugView.swift

The debug panel provides testing capabilities:

**Configuration Inspection:**
```swift
let version = bunting.configVersion
let published = bunting.publishedAt
let verified = bunting.signatureVerified
```

**Identity Management:**
```swift
let id = bunting.localID
try await bunting.resetIdentity()  // async — generates new UUID
```

**Local Overrides:**
```swift
// Set override (takes precedence over backend value)
bunting.setOverride("feature/enabled", value: true)

// Clear specific override
bunting.clearOverride("feature/enabled")

// Clear all overrides
bunting.clearAllOverrides()
```

**Key Points:**
- Overrides persist in UserDefaults across app launches
- Useful for QA testing without backend changes
- Resetting identity helps test different rollout buckets

### BuntingConfig.plist

Configuration file for the SDK:

```xml
<key>endpoint_url</key>
<string>https://cdn.example.com/bunting/your-app/config.json</string>

<key>public_keys</key>
<array>
    <dict>
        <key>kid</key>
        <string>key-2025-01</string>
        <key>pem</key>
        <string>-----BEGIN PUBLIC KEY-----
        ...your RSA public key...
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
```

**Key Points:**
- Must be included in app bundle (check Target Membership)
- `endpoint_url`: Where to fetch configuration
- `public_keys`: For JWS signature verification
- `fetch_policy`: Rate limiting and cache TTL

## 🎯 Usage Patterns

### Environment-Specific Configuration

```swift
// Bunting supports three environments
try? Bunting.configure(environment: .development)  // Dev flags
try? Bunting.configure(environment: .beta)      // Beta flags
try? Bunting.configure(environment: .production)   // Production flags
```

### Custom Attributes

For advanced targeting based on app state:

```swift
try? Bunting.configure(
    environment: .production,
    customAttributes: { attribute in
        switch attribute {
        case "is_premium":
            return UserDefaults.standard.bool(forKey: "isPremium")
        case "has_completed_onboarding":
            return UserDefaults.standard.bool(forKey: "onboarded")
        default:
            return false
        }
    }
)
```

Then in your backend configuration, you can target:

```json
{
  "conditions": [
    {
      "type": "custom_attribute",
      "values": ["is_premium"],
      "operator": "custom"
    }
  ]
}
```

### Sharing Identity Across Apps

Use a keychain access group to share identity:

```swift
try? Bunting.configure(
    environment: .production,
    keychainAccessGroup: "group.com.yourcompany.shared"
)
```

This ensures users get the same experience across all your apps.

## 🧪 Testing

### Without a Backend

The app works offline-first:

1. **Default Values**: All flags return their defaults
2. **Local Overrides**: Use the Debug Panel to test different values
3. **No Network Required**: SDK falls back gracefully

### With Local Backend

For development, you can run a local backend:

1. Update `endpoint_url` to `http://localhost:3000/config.json`
2. Run your Bunting admin locally
3. Publish test configurations

### Testing Different Buckets

1. Open Debug Panel
2. Note your current Local ID
3. Tap "Reset Identity" to get a new UUID
4. This may place you in a different rollout bucket

## 🔍 Troubleshooting

### App Crashes on Launch

**Problem**: "BuntingConfig.plist not found"

**Solution**: 
1. Select `BuntingConfig.plist` in Xcode
2. Open File Inspector (⌘⌥1)
3. Check "Target Membership" → ✓ BuntingExample

### Flags Always Return Defaults

**Problem**: Configuration not loading

**Solutions**:
1. Check `endpoint_url` is reachable
2. Verify signature verification (Debug Panel)
3. Check Xcode console for Bunting logs
4. Try "Refresh Configuration" button

### Signature Not Verified

**Problem**: "Signature: Not Verified" in Debug Panel

**Solutions**:
1. Verify public key in `BuntingConfig.plist` matches private key on backend
2. Check `kid` (key ID) matches between config and backend
3. Ensure JWS signature format is correct

### Changes Don't Appear

**Problem**: Updated config but app shows old values

**Solutions**:
1. Tap "Refresh Configuration" to fetch latest
2. Check if enough time has passed (respects `min_interval_seconds`)
3. Clear app data and reinstall to reset cache

## 📚 Learning Resources

### Understanding the Code

**Start here:**
1. `BuntingExampleApp.swift` - See configuration
2. `ContentView.swift` - See flag access patterns
3. `DebugView.swift` - See testing capabilities

**Key concepts to understand:**
- Async/await for all flag access
- Environment-based configuration
- Default values as fallbacks
- Offline-first operation
- Local overrides for testing

### Modifying the Example

**Add a new flag:**

1. In `ContentView.swift`, add a state variable:
   ```swift
   @State private var myNewFlag = false
   ```

2. In `loadFlags()`, fetch the value:
   ```swift
   myNewFlag = bunting.bool("my/new_flag", default: false)
   ```

3. In the UI, display it:
   ```swift
   Toggle("My New Feature", isOn: .constant(myNewFlag))
   ```

4. Define the flag in your backend configuration

**Add a new override:**

1. In `DebugView.swift`, add a state variable:
   ```swift
   @State private var myFlagOverride: Bool?
   ```

2. Add a toggle in the UI:
   ```swift
   Toggle("My Flag", isOn: Binding(
       get: { myFlagOverride ?? false },
       set: { newValue in
           myFlagOverride = newValue
           Task {
               await setFlagOverride(key: "my/new_flag", value: newValue)
           }
       }
   ))
   ```

## 🎨 Customization Ideas

Try these modifications to learn more:

1. **Add a theme switcher** - Use a string flag for "light"/"dark"/"auto"
2. **Show JSON config visually** - Parse and display JSON flag data
3. **Add history** - Track configuration version changes
4. **Export feature** - Export current config as JSON
5. **Network indicator** - Show when fetching from backend

## 📄 Sample Configuration

The app expects these flags (all optional):

| Flag Key | Type | Default | Description |
|----------|------|---------|-------------|
| `store/use_new_paywall_design` | boolean | `false` | Enable new paywall UI |
| `ui/welcome_message` | string | `"Welcome!"` | Welcome text |
| `features/max_upload_size` | integer | `25` | Max upload MB |
| `ui/theme_color` | string | `"#007AFF"` | Theme color hex |
| `features/discount_percentage` | double | `0.10` | Discount rate |

See `../Examples/sample-config.json` for a complete configuration example.

## 🆘 Support

For questions or issues:

1. Check the main SDK [README](../README.md)
2. Review the [specification docs](../../../docs/)
3. Open an issue in the repository

## 📝 License

Same as the main Bunting project.
