# Bunting Package Plugins

This directory contains Swift Package Manager plugins for the Bunting SDK. These plugins help automate configuration fetching and code generation during development.

**Note:** Both plugins support Swift packages and Xcode projects through the `XcodeProjectPlugin` protocol.

## Available Plugins

### 1. FetchConfigPlugin (Command Plugin)

A command plugin that fetches the latest Bunting configuration from your backend.

#### Usage

In Xcode:
1. Right-click on your project or package in the Project Navigator
2. Select **Bunting** → **Fetch Config**
3. The plugin will read your `BuntingConfig.plist` and fetch the latest configuration

From command line:
```bash
swift package plugin fetch-config
```

#### Requirements

- A valid `BuntingConfig.plist` file in one of these locations:
  - Project root
  - `Resources/` directory
  - App target's resource bundle

#### What It Does

1. Locates your `BuntingConfig.plist` file
2. Reads the configuration endpoint and signing keys
3. Fetches `config.json` from the endpoint
4. Validates the JWS signature in the `x-bunting-signature` header
5. Saves the configuration to `BuntingConfig.json` in your project

This is useful for:
- Testing with the latest production flags during development
- Updating your seed configuration before building
- Verifying your backend is serving valid configurations

---

### 2. BuntingCodegenPlugin (Build Tool Plugin)

A build tool plugin that automatically generates strongly-typed Swift accessors for your feature flags.

#### Usage

This plugin runs automatically during builds. No manual invocation needed.

#### Requirements

- A `BuntingConfig.json` file in your project root containing flag definitions

#### What It Does

1. Reads `BuntingConfig.json` at build time
2. Extracts all flag definitions
3. Generates nested Swift namespaces based on flag keys
4. Creates strongly-typed accessor properties

#### Generated Code Example

Given flags in your configuration:
```json
{
  "flags": {
    "store/use_new_paywall_design": {
      "type": "bool",
      "default": false
    },
    "store/paywall_title": {
      "type": "string", 
      "default": "Upgrade Now"
    }
  }
}
```

The plugin generates:
```swift
extension Bunting {
    public var store: StoreNamespace {
        StoreNamespace(bunting: self)
    }
    
    public struct StoreNamespace {
        let bunting: Bunting
        
        public var useNewPaywallDesign: Bool {
            get async {
                bunting.bool("store/use_new_paywall_design", default: false)
            }
        }
        
        public var paywallTitle: String {
            get async {
                bunting.string("store/paywall_title", default: "Upgrade Now")
            }
        }
    }
}
```

#### Usage in Your Code

Instead of using string keys:
```swift
let enabled = Bunting.shared.bool("store/use_new_paywall_design", default: false)
```

Use strongly-typed accessors:
```swift
let enabled = await Bunting.shared.store.useNewPaywallDesign
```

Benefits:
- **Type safety**: Compile-time checking of flag types
- **Autocomplete**: Xcode suggests available flags
- **Refactoring**: Rename flags safely across your codebase
- **Documentation**: Generated code shows default values and types

---

## Command-Line Tools

The plugins use two underlying command-line tools:

### bunting-cli

Fetches configuration from your backend.

**Usage:**
```bash
bunting-cli /path/to/BuntingConfig.plist
```

**Output:**
- Saves `BuntingConfig.json` in the same directory as the plist
- Prints status messages to stdout
- Returns exit code 0 on success, 1 on failure

### bunting-codegen

Generates Swift code from configuration.

**Usage:**
```bash
bunting-codegen /path/to/BuntingConfig.json /path/to/output.swift
```

**Output:**
- Creates Swift source file with generated accessors
- Returns exit code 0 on success, 1 on failure

---

## Workflow

### Typical Development Workflow

1. **Initial Setup**
   - Create `BuntingConfig.plist` with your backend endpoint and signing keys
   - Run **Fetch Config** plugin to download initial configuration
   - This creates `BuntingConfig.json` in your project

2. **During Development**
   - Edit flags in your admin panel
   - Periodically run **Fetch Config** to get latest flags
   - Build your app - codegen runs automatically
   - Use strongly-typed accessors in your code

3. **Before Release**
   - Run **Fetch Config** one final time
   - The `BuntingConfig.json` becomes your app's seed configuration
   - Bundle this file with your app for offline-first support

### CI/CD Integration

In your build pipeline:

```bash
# Fetch latest config
swift package plugin fetch-config

# Build with codegen
swift build

# Or for Xcode projects
xcodebuild build
```

---

## Troubleshooting

### "BuntingConfig.plist not found"

The `FetchConfigPlugin` looks in:
- Project root
- `Resources/` directory
- Common app target locations

Ensure your plist is in one of these locations, or update the plugin's search paths in `Plugins/FetchConfigPlugin/plugin.swift`.

### "BuntingConfig.json not found"

The `BuntingCodegenPlugin` requires a seed configuration file. Run the `FetchConfigPlugin` first to download it from your backend.

### Generated Code Not Updating

1. Clean build folder: **Product** → **Clean Build Folder** (Shift-Cmd-K)
2. Delete `DerivedData`
3. Rebuild project

### Signature Verification Failed

Check that:
- Your `BuntingConfig.plist` contains the correct public keys
- The keys match those used by your backend to sign configurations
- The backend is returning the JWS signature in the `x-bunting-signature` header

---

## Customization

### Modifying Plugin Behavior

Both plugins are implemented in Swift and can be customized:

- **FetchConfigPlugin**: `Plugins/FetchConfigPlugin/plugin.swift`
  - Modify plist search paths
  - Add custom validation logic
  - Change output location

- **BuntingCodegenPlugin**: `Plugins/BuntingCodegenPlugin/plugin.swift`
  - Adjust code generation triggers
  - Add custom build commands

### Modifying CLI Tools

- **bunting-cli**: `Sources/bunting-cli/main.swift`
  - Add caching logic
  - Support additional authentication methods
  - Add retry logic for network failures

- **bunting-codegen**: `Sources/bunting-codegen/main.swift`
  - Customize naming conventions
  - Add documentation comments to generated code
  - Support additional flag types

---

## Security Notes

- **Never commit signing private keys** to version control
- The `bunting-cli` tool only uses public keys for signature verification
- Configuration files (`BuntingConfig.json`) are safe to commit and bundle with your app
- The plist file contains only public keys and endpoint URLs

---

## Learn More

- [WWDC 2022: Create Swift Package plugins](https://developer.apple.com/videos/play/wwdc2022/110359/)
- [WWDC 2022: Meet Swift Package plugins](https://developer.apple.com/videos/play/wwdc2022/110401/)
- [Swift Package Manager Plugin Documentation](https://github.com/apple/swift-package-manager/blob/main/Documentation/Plugins.md)
