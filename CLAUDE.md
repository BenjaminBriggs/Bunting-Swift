# Bunting Swift SDK — AI Assistant Guide

Bunting is a self-hosted feature flag system for Apple platforms. This SDK fetches a
signed JSON config artifact from a CDN, verifies it offline using RS256, caches it on
disk, and evaluates all flags locally with no server round-trips at read time.

**See [README.md](README.md) for full usage, API reference, and integration guide.**

## Source tree

```
Sources/
  Bunting/              # Core SDK library
    Models/             # Config, Flag, Variant, Condition data types
    Evaluation/         # FlagEvaluator (stateless), ConditionEvaluator, MemoizationCache
    Storage/            # ConfigStore (actor), OverridesStore (actor)
    Security/           # JWS/RS256 signature verification
    Identity/           # BuntingIdentity (actor) — iCloud Keychain-backed UUID
    SwiftUI/            # BuntingInfoView, BuntingDebugView, EnvironmentValues
  bunting-cli/          # Executable: fetches config.json from backend (used by FetchConfigPlugin)
  bunting-codegen/      # Executable: generates typed Swift accessors from config JSON

Plugins/
  FetchConfigPlugin/    # Command plugin — wraps bunting-cli; run via `swift package plugin fetch-config`
  BuntingCodegenPlugin/ # Build tool plugin — wraps bunting-codegen; runs automatically at build time

Tests/
  BuntingTests/         # Unit tests (bucketing, evaluation, signature, identity)

Example/
  BuntingExample.xcodeproj
  BuntingExample/       # iOS demo app
  README.md             # Example app walkthrough

docs/
  architecture.md       # Concurrency model, evaluation engine, caching, memoization
  plugins.md            # FetchConfigPlugin + BuntingCodegenPlugin reference
  quick-reference.md    # Cheat sheet of common SDK operations
```

## Dev commands

```bash
swift build                                   # Build all targets
swift test                                    # Run unit tests
swift package plugin fetch-config            # Download config.json from BuntingConfig.plist endpoint
swift package generate-documentation --target Bunting  # Build DocC
```

## Canonical facts

The single source of truth for platforms, environments, flag types, signing, the bootstrap plist, and the fallback chain is the human documentation — do not restate or duplicate it here (that is how docs drift):

- `README.md` — full usage and API reference
- `docs/` (this repo) — `architecture.md`, `plugins.md`, `quick-reference.md`
- `../docs/` (Bunting root) — cross-cutting system docs (see `../docs/README.md`)

## Key conventions

**Synchronous flag accessors** — `bool/string/int/double/date/jsonData(key:default:)` are
`@MainActor` synchronous. Never add `await` to a flag read. Only `refresh()` and
`resetIdentity()` are `async`. Override methods (`setOverride`, `clearOverride`,
`clearAllOverrides`) and status properties (`configVersion`, `publishedAt`,
`signatureVerified`, `configSource`, `localID`) are also synchronous.

**Concurrency model** — `Bunting` is a `@MainActor @Observable` class. Internal components
(`ConfigStore`, `OverridesStore`, `BuntingIdentity`) are Swift actors. Flag reads operate
from `@MainActor` in-memory snapshots primed at startup — there is no actor hop at read time.

**Codegen never fails the build** — if `BuntingConfig.json` is missing or invalid,
`BuntingCodegenPlugin` emits an empty `BuntingPaths` fallback. String-based access always
works; typed accessor paths (e.g., `\.store.myFlag`) compile only once the seed JSON is present.

**No force-unwraps in production paths** — use guarded unwraps or provide defaults.

**Evaluation order**: override → first matching variant (ascending `order`) → environment default.
Conditions within a variant are ANDed; use separate variants with lower `order` to express OR.

**Bucketing**: `SHA-256("\(salt):\(localID)")` → first 8 bytes big-endian UInt64 → `(value % 100) + 1` → bucket 1–100.

**watchOS**: no foreground notification observer — call `refresh()` manually if needed.
