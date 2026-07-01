# Bunting Swift SDK

A self-hosted, open-source feature flag and rollout system for Apple platforms.

## Features

- **Offline-First**: Local evaluation with signed artifact verification
- **Strongly-Typed**: Generated accessors for type-safe flag access (with resilient fallback)
- **Secure**: JWS signature verification with RS256
- **Privacy-Preserving**: Deterministic bucketing with device-local UUID
- **Multi-Environment**: Support for development, beta, and production
- **Debug UI**: Built-in override and inspection tools
- **Build Resilient**: Codegen never fails builds — automatically falls back when config is missing

## Requirements

- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- Swift 6.0+
- Xcode 16+

## Installation

### Swift Package Manager

Add Bunting to your `Package.swift`:

```swift
dependencies: [
    // Replace with the actual URL once the repo is published
    .package(url: "https://github.com/<your-org>/bunting-sdk-swift.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File > Add Package Dependencies
2. Enter the repository URL
3. Select your target and add the package

## Example App

A complete iOS example application is available in the `Example/` directory demonstrating:

- Basic integration and configuration
- Reading all flag types
- Debug panel with overrides
- Configuration inspection
- Identity management

**Quick start**: See [docs/quick-reference.md](docs/quick-reference.md) for a cheat sheet of common operations.

## Quick Start

### 1. Add Bootstrap Configuration

Create `BuntingConfig.plist` in your app bundle (ensure **Target Membership** is checked):

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

`fetch_policy` is required — the SDK has no built-in fallback for these values.

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

Flag accessors are synchronous — no `await` needed:

```swift
import Bunting

struct ContentView: View {
    var body: some View {
        VStack {
            if Bunting.shared.bool("store/use_new_paywall_design", default: false) {
                NewPaywallView()
            } else {
                OldPaywallView()
            }
        }
    }
}
```

## Flag Types

Bunting supports six flag types. All accessors are synchronous (`@MainActor`):

```swift
// Boolean
let enabled = Bunting.shared.bool("feature/enabled", default: false)

// String
let message = Bunting.shared.string("ui/welcome_message", default: "Hello")

// Integer
let maxSize = Bunting.shared.int("features/max_upload_size", default: 25)

// Double
let discount = Bunting.shared.double("features/discount", default: 0.10)

// Date (ISO 8601 on the wire)
let deadline = Bunting.shared.date("features/deadline", default: Date())

// JSON (UTF-8 encoded; returned as Data)
if let data = Bunting.shared.jsonData("layout/home_sections") {
    let sections = try? JSONDecoder().decode(HomeSections.self, from: data)
}
```

Only `refresh()` and `resetIdentity()` are `async`.

## Configuration

### Environment Selection

Three environments are available:

```swift
#if DEBUG
try? Bunting.configure(environment: .development)
#elseif BETA
try? Bunting.configure(environment: .beta)
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

For sharing identity across apps in the same team:

```swift
try? Bunting.configure(
    environment: .production,
    keychainAccessGroup: "group.com.example.shared"
)
```

## Manual Refresh

Trigger a config refresh manually (async):

```swift
await Bunting.shared.refresh()
```

## Debug Overrides

Set local overrides for testing (synchronous):

```swift
// Set override
Bunting.shared.setOverride("store/use_new_paywall_design", value: true)

// Clear specific override
Bunting.shared.clearOverride("store/use_new_paywall_design")

// Clear all overrides
Bunting.shared.clearAllOverrides()
```

## SwiftUI Debug Views

Bunting includes built-in SwiftUI views for debugging and development:

### BuntingInfoView (Read-Only)

Display configuration status and metadata:

```swift
import SwiftUI
import Bunting

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            BuntingInfoView()
        }
    }
}
```

Shows:
- Current environment
- Config version and publication date
- Signature verification status
- Device identity (local ID)
- Pull-to-refresh support

### BuntingDebugView (Interactive)

Full debug panel with override controls:

```swift
import SwiftUI
import Bunting

struct DebugMenuView: View {
    var body: some View {
        NavigationStack {
            BuntingDebugView()
        }
    }
}
```

Features:
- All information from `BuntingInfoView`
- Per-flag display grouped by namespace
- Set/clear flag overrides
- Manual refresh trigger
- Reset identity with confirmation
- Clear all overrides with confirmation

### SwiftUI Environment Access

Access Bunting via SwiftUI environment:

```swift
struct MyView: View {
    @Environment(\.bunting) var bunting

    var body: some View {
        Text("Config version: \(bunting.configVersion ?? "unknown")")
    }
}
```

## Event Observability

Implement `BuntingEventsDelegate` to observe lifecycle events:

```swift
import Bunting
import OSLog

class BuntingObserver: BuntingEventsDelegate {
    private let logger = Logger(subsystem: "com.example.app", category: "bunting")

    func didStartFetch(url: URL) {
        logger.info("Fetching config from \(url)")
    }

    func didCompleteFetch(success: Bool, error: Error?) {
        if success {
            logger.info("Config fetch succeeded")
        } else {
            logger.error("Config fetch failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    func didVerifySignature(success: Bool) {
        logger.info("Signature verification: \(success ? "passed" : "failed")")
    }

    func didLoadCachedConfig(version: String) {
        logger.info("Loaded cached config version \(version)")
    }

    func didChangeOverride(flagKey: String, value: Any?) {
        if let value {
            logger.debug("Override set: \(flagKey) = \(value)")
        } else {
            logger.debug("Override cleared: \(flagKey)")
        }
    }
}

// Set the delegate
let observer = BuntingObserver()
Bunting.shared.eventsDelegate = observer
```

Available delegate methods (all optional):
- `didStartFetch(url:)` — Config fetch initiated
- `didCompleteFetch(success:error:)` — Config fetch completed
- `didVerifySignature(success:)` — Signature verification result
- `didLoadCachedConfig(version:)` — Cached config loaded
- `didChangeOverride(flagKey:value:)` — Override changed

## Identity Management

Reset the local identity (generates a new UUID, invalidates the memoization cache):

```swift
try await Bunting.shared.resetIdentity()
```

The device identity is stored in iCloud Keychain and survives app reinstalls. It is never transmitted — used only for local bucketing.

## Config Fingerprint

`userFingerprint` returns a compact `<config_version>.<HEX>` string that captures exactly which resolution path every flag took for the active environment and this device — useful to attach to support tickets, logs, or analytics. It is synchronous and returns `nil` until a configuration and the device identity have loaded.

```swift
if let fingerprint = Bunting.shared.userFingerprint {
    logger.info("config fingerprint: \(fingerprint)")
}
```

Paste the string into the Bunting admin to decode it back to each flag's resolved value and the reason it resolved that way, without re-running evaluation. The fingerprint reflects the published artifact's resolution for this client; local overrides are not included.

## Architecture

### Components

- **ConfigStore**: Manages fetching, signature verification, and caching of configuration (Swift actor)
- **BuntingIdentity**: Keychain-backed persistent UUID for deterministic bucketing (Swift actor)
- **FlagEvaluator**: Stateless condition and flag evaluation engine
- **OverridesStore**: Local flag override management backed by `UserDefaults` (Swift actor)
- **MemoizationCache**: In-memory cache keyed by flag + environment + context hash; invalidated on config refresh or override change

### Data Flow

1. **Bootstrap**: Load `BuntingConfig.plist` from the app bundle (endpoint URL, public keys, fetch policy)
2. **Fetch**: Download signed configuration from CDN with ETag caching
3. **Verify**: Validate JWS (RS256) signature using public key matched by `kid`
4. **Cache**: Persist verified config atomically to Application Support
5. **Evaluate**: Resolve flags locally using conditions, tests, and rollouts
6. **Override**: Apply local overrides (highest precedence)

### Evaluation Order

For each flag in the active environment:

1. Check local overrides (highest priority)
2. Iterate variants by ascending `order`:
   - **Conditional**: all conditions pass → return `value`
   - **Test**: all conditions pass → bucket user → return group value
   - **Rollout**: all conditions pass → bucket user → return `value` if bucket ≤ percentage
3. Return environment default (fallback)

First match wins.

### Config Fallback Chain

On fetch failure or signature verification failure:

1. Last successfully verified cached config (Application Support)
2. Bundled seed `BuntingConfig.json` (if present in app bundle)
3. Code-provided default values

### Bucketing Algorithm

Deterministic bucketing for tests and rollouts:

1. Concatenate `salt:localID` (e.g., `"unique-salt:550E8400-..."`)
2. Compute SHA-256 hash of UTF-8 bytes
3. Take first 8 bytes as unsigned big-endian UInt64
4. Return `(value % 100) + 1` → bucket 1–100

The same `(salt, localID)` pair always produces the same bucket. Changing the salt re-randomises enrollment.

## Strongly-Typed Accessors (Codegen)

The `BuntingCodegenPlugin` build tool plugin generates type-safe accessors from a bundled `BuntingConfig.json`. Accessors use `/`-delimited namespaces and snake_case → camelCase conversion:

```swift
// Generated from flag key "store/use_new_paywall_design"
Bunting.shared.store.useNewPaywallDesign  // Bool, synchronous
```

Fetch the seed config using the command plugin:

```bash
swift package plugin fetch-config
```

The build plugin runs automatically. If `BuntingConfig.json` is absent or invalid, the plugin generates an empty `BuntingPaths` fallback so the build never fails. See [Plugins reference](docs/plugins.md) for full details.

## Testing

Run unit tests:

```bash
swift test
```

Tests cover:
- Deterministic bucketing algorithm
- Condition evaluation (platform, version, region, locale)
- Flag resolution with variant ordering
- Keychain identity persistence

## Security

### Signature Verification

All configurations are signed with RS256:

1. Admin backend signs `config.json` with a private key
2. Detached JWS signature delivered in the `x-bunting-signature` response header
3. SDK verifies offline using the matching public key (looked up by `kid`)
4. On verification failure, the response is discarded and the cached config is retained

### Key Rotation

Multiple public keys supported via `kid` for zero-downtime rotation:

```xml
<key>public_keys</key>
<array>
    <dict>
        <key>kid</key>
        <string>key-2025-01</string>
        <key>pem</key>
        <string>... new public key ...</string>
    </dict>
    <dict>
        <key>kid</key>
        <string>key-2024-12</string>
        <key>pem</key>
        <string>... old public key ...</string>
    </dict>
</array>
```

Publish with both keys in the plist, rotate the signing key in the admin backend, then remove the old key in a subsequent app release.

### Privacy

- Local ID stored in iCloud Keychain (survives reinstall)
- Never transmitted to any server
- Used only for deterministic bucketing
- Resettable via `resetIdentity()`

## Performance

- **Flag lookup**: < 2µs (memoized), < 100µs (cold)
- **Config parse**: < 25ms for 5K flags
- **Memory**: < 5MB typical

## Limitations (v1)

- No real-time updates (periodic polling only)
- No built-in analytics or exposure tracking
- No server-side evaluation
- Apple platforms only

## Documentation

| Document | Description |
|---|---|
| [GettingStarted](Sources/Bunting/Bunting.docc/GettingStarted.md) | Step-by-step setup and first flag access |
| [UnderstandingVariants](Sources/Bunting/Bunting.docc/UnderstandingVariants.md) | Conditional, test, and rollout variant types |
| [ABTesting](Sources/Bunting/Bunting.docc/ABTesting.md) | Running multi-group experiments |
| [GradualRollouts](Sources/Bunting/Bunting.docc/GradualRollouts.md) | Percentage-based feature deployment |
| [Architecture](docs/architecture.md) | Component overview, concurrency model, evaluation engine |
| [Plugins reference](docs/plugins.md) | FetchConfigPlugin and BuntingCodegenPlugin reference |
| [Example/](Example/README.md) | Complete iOS demo app with debug panel |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Build gate, doc-comment expectations, DocC generation |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

Generate full API documentation locally:

```bash
swift package generate-documentation --target Bunting
```

### Companion resources

- **Admin UI**: [BenjaminBriggs/Bunting-Admin](https://github.com/BenjaminBriggs/Bunting-Admin) — the web interface for authoring and publishing flag configurations
- **Config artifact spec**: `docs/config-artifact-spec.md` in the admin repo — the canonical contract between the admin backend and this SDK

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build requirements, doc-comment expectations,
and how to run the DocC build locally.

## License

MIT — see [LICENSE](LICENSE).

## Support

For issues and questions, open an issue in the main Bunting repository.
