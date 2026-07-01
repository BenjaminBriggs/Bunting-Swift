# Bunting Swift Package Plugins

The Bunting SDK includes two Swift Package Manager plugins to streamline your development workflow. Both plugins work with Swift packages and Xcode projects.

## Quick Start

### 1. Fetch Latest Configuration

Right-click on your package in Xcode → **Bunting** → **Fetch Config**

Or from command line:
```bash
swift package plugin fetch-config
```

This downloads the latest configuration from your backend and saves it as `BuntingConfig.json`.

### 2. Generate Typed Accessors

This happens automatically during builds once you have a `BuntingConfig.json` file in your project.

**Note:** The codegen plugin is **optional**. If `BuntingConfig.json` is not found, the build will succeed but skip code generation. You can still use string-based flag access without it.

The plugin generates strongly-typed Swift accessors from your flag definitions.

## Plugin Details

### FetchConfigPlugin (Command Plugin)

**Purpose**: Download and verify configuration from your backend

**How to use**:
- In Xcode: Right-click project → Bunting → Fetch Config
- Command line: `swift package plugin fetch-config`

**Requirements**:
- `BuntingConfig.plist` in your project (with endpoint URL and public keys)

**What it does**:
1. Locates your `BuntingConfig.plist`
2. Fetches `config.json` from the configured endpoint
3. Reads the compact JWS from the `x-bunting-signature` response header; if absent, fetches `<endpoint>.sig`
4. Verifies the RS256 signature over the exact fetched bytes
5. Saves the verified config to `BuntingConfig.json` (only written after verification succeeds)

---

### BuntingCodegenPlugin (Build Tool Plugin)

**Purpose**: Generate strongly-typed flag accessors at compile time

**How to use**: Runs automatically during builds

**Requirements**:
- `BuntingConfig.json` in your project root (optional - see Fallback Mode below)

**Fallback Mode**:

The codegen plugin is designed to **never fail your build**. If `BuntingConfig.json` is missing or invalid, the plugin automatically generates a minimal fallback file that:
- Defines empty `BuntingPaths` structure (required by `@BuntingFlag` property wrapper)
- Includes `FlagDescriptor<T>` type definition
- Contains no flag-specific accessors
- Allows your code to compile even if typed accessors aren't available yet

This means:
✅ Your builds always succeed
✅ No need to comment out `@BuntingFlag` usage during development
✅ Easy onboarding - typed flags work as soon as you add config
⚠️ Compilation errors if you try to use non-existent flag paths (e.g., `\.store.myFlag`)

To enable typed accessors, simply add `BuntingConfig.json` and rebuild.

**What it generates**:

Given this flag definition:
```json
{
  "flags": {
    "store/use_new_paywall_design": {
      "type": "bool",
      "default": false
    }
  }
}
```

Generates:
```swift
extension Bunting {
    public var store: StoreNamespace {
        StoreNamespace(bunting: self)
    }
    
    public struct StoreNamespace {
        let bunting: Bunting
        
        public var useNewPaywallDesign: Bool {
            get {
                bunting.bool("store/use_new_paywall_design", default: false)
            }
        }
    }
}
```

**Benefits**:
- Type safety at compile time
- Xcode autocomplete for all flags
- Refactor flags safely
- Clear documentation of defaults

**Note:** The default baked into each generated accessor comes from the seed's
**development** environment value for that flag, not the environment the app runs in.
Date flags always bake `Date()` (evaluated at access time) as a placeholder, since a
literal date can't be embedded as source. These generated defaults are a last resort —
at runtime, `Bunting.shared` always evaluates flags against the fetched config for the
configured environment; the compile-time default is only used if no config (fetched,
cached, or seed) is available at all.

## Workflow

### Initial Setup

1. Create `BuntingConfig.plist` with your backend endpoint and public keys
2. Run **Fetch Config** plugin
3. Build your project (codegen runs automatically)
4. Use typed accessors in your code

### During Development

```swift
// Instead of string keys:
let enabled = Bunting.shared.bool("store/use_new_paywall_design", default: false)

// Use typed accessors:
let enabled = Bunting.shared.store.useNewPaywallDesign
```

### Before Release

1. Run **Fetch Config** to get latest production flags
2. The downloaded `BuntingConfig.json` becomes your app's seed configuration
3. Bundle it with your app for offline-first support

## Underlying Tools

The plugins use two command-line executables:

### bunting-cli

Fetches configuration from your backend, verifies the signature, and writes the output only
after verification succeeds.

```bash
bunting-cli /path/to/BuntingConfig.plist [output-path]
```

Exit codes: `1` usage/plist/file-system error, `2` network error, `3` signature missing or failed, `4` config JSON decode failed.

### bunting-codegen

Generates Swift code from configuration.

```bash
bunting-codegen /path/to/BuntingConfig.json /path/to/output.swift
```

## Troubleshooting

### "BuntingConfig.plist not found"

Ensure your plist file is in one of these locations:
- Project root
- `Resources/` directory
- `Example/BuntingExample/` directory

### "BuntingConfig.json not found" or Invalid Config

**Don't worry - your builds will still succeed!** The codegen plugin automatically generates a fallback file when the config is missing or invalid.

To enable strongly-typed flag accessors, you have two options:

**Option 1: Fetch from backend (Recommended)**
- In Xcode: Right-click project → **Bunting** → **Fetch Config**
- Command line: `swift package plugin fetch-config`

**Option 2: Create manually**
- Download config from your Bunting admin panel
- Save as `BuntingConfig.json` in project root or app target directory

**During fallback mode:**
- Use string-based flag access: `Bunting.shared.bool("my/flag", default: false)`
- Don't use `@BuntingFlag` property wrapper (will cause compile errors for non-existent paths)
- Check build logs for: `⚠️  Generated fallback accessors (no config available)`

### Generated code not updating

1. Clean build: Product → Clean Build Folder (⇧⌘K)
2. Rebuild project

### Signature verification failed

Check that:
- Public keys in `BuntingConfig.plist` match your backend's signing keys
- The backend either injects the compact JWS in the `x-bunting-signature` response header, or serves a sibling `<endpoint>.sig` file at the same path
- Configuration endpoint is accessible

## CI/CD Integration

```bash
# Fetch latest config in your build pipeline
swift package plugin fetch-config

# Build normally - codegen runs automatically
swift build
```

## Learn More

- [Plugin Implementation Details](Plugins/README.md)
- [WWDC 2022: Create Swift Package plugins](https://developer.apple.com/videos/play/wwdc2022/110359/)
- [WWDC 2022: Meet Swift Package plugins](https://developer.apple.com/videos/play/wwdc2022/110401/)
