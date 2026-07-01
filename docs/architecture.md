# Bunting Swift SDK — Architecture

## Overview

The SDK is a locally-evaluating feature flag client for Apple platforms. It fetches a
signed JSON config artifact from a CDN, verifies the signature, caches the artifact
on disk, and evaluates all flags in-process with no server round-trips at read time.

```
App binary
  └── Bunting (@MainActor @Observable class)
        ├── ConfigStore (actor)   — fetch, verify, cache
        ├── OverridesStore (actor) — developer overrides via UserDefaults
        ├── BuntingIdentity (actor) — keychain-backed device UUID
        ├── MemoizationCache      — sub-µs repeated reads
        └── FlagEvaluator         — stateless, created per evaluation
```

## Concurrency Model

`Bunting` is a `@MainActor`-isolated `@Observable` class. All public flag-access
methods are synchronous and safe to call from SwiftUI body or any `@MainActor` context.

Internal components (`ConfigStore`, `OverridesStore`, `BuntingIdentity`) are Swift
actors. They manage their own isolated state and expose async interfaces. `Bunting`
talks to them asynchronously but exposes synchronous read paths by working from
in-memory snapshots:

- On startup a `Task` primes the snapshots (loads cached config, overrides, local ID).
- `configuration`, `overridesSnapshot`, and `cachedLocalID` are `@MainActor` properties
  updated whenever the underlying actors report a change.
- Flag reads consult only these snapshots — no `await` at read time.

## Flag Evaluation Engine

`FlagEvaluator` is a stateless struct created per evaluation request. The algorithm:

1. **Override check**: if `overridesSnapshot[key]` is set, return it immediately.
2. **Memoization**: compute a `CacheKey` from `(flagKey, environment, contextHash,
   overridesVersion, configVersion)`. Return the cached result if present.
3. **Variant loop**: retrieve the flag's `EnvironmentConfig` for the active environment,
   sort variants by ascending `order`, and evaluate each:
   - **Conditional**: all `conditions` must pass → return `value`.
   - **Test**: all `conditions` must pass → bucket user → look up group name in `values`.
   - **Rollout**: all `conditions` must pass → bucket user → return `value` if bucket ≤ percentage.
4. **Fallback**: return `EnvironmentConfig.default`.

First match wins. No variant is reconsidered after a match.

### Condition Evaluation

`ConditionEvaluator` handles each `ConditionType`:

| Type | Operators |
|---|---|
| `os_version`, `app_version`, `build_number` | `equals`, `does_not_equals`, `between`, `greater_than`, `greater_than_or_equal`, `less_than`, `less_than_or_equal` |
| `platform`, `device_model`, `region` | `in`, `not_in` |
| `locale` | `equals` (exact), `in` / `not_in` (prefix match) |
| `custom_attribute` | `custom` — delegates to the app-supplied resolver closure |

Conditions within a list are ANDed. There is no built-in OR; use separate variants with
lower `order` values to express OR logic.

### Bucketing Algorithm

Used by both `Test` and `Rollout` variants to assign users deterministically:

```
input  = UTF-8 bytes of "\(salt):\(localID)"
hash   = SHA-256(input)
value  = first 8 bytes interpreted as big-endian UInt64
bucket = (value % 100) + 1          // result: 1–100
```

The same `(salt, localID)` pair always produces the same bucket. Changing the salt
re-randomises enrollment. The local ID is the device's keychain-backed UUID, so it
persists across reinstalls and is shared across the developer's apps when a
`keychainAccessGroup` is configured.

## Configuration Storage and Caching

`ConfigStore` manages the full lifecycle of the config artifact:

1. **Bootstrap**: reads `BuntingConfig.plist` from the app bundle to get the CDN
   endpoint URL, public keys, and fetch policy.
2. **ETag caching**: issues conditional `GET` requests with `If-None-Match`. A
   `304 Not Modified` response skips parsing and signature verification entirely.
3. **Hard TTL**: forces a refresh after `hard_ttl_days` days regardless of ETags,
   defending against a CDN serving a stale response indefinitely.
4. **Rate limiting**: respects `min_interval_seconds` between fetches to prevent
   hammering the CDN on every foreground resume.
5. **Atomic writes**: the verified config bytes and their detached JWS are written to
   `Application Support` atomically. The signature (`config_v1.json.sig`) is written first
   so that a crash between the two writes leaves an unverifiable pair rather than a
   silently unverified config.
6. **Metadata persistence**: ETag, last-fetch timestamp, and TTL are persisted alongside
   the config so rate limiting and TTL survive process restarts.

On fetch failure or signature verification failure, `ConfigStore` falls back to the
last cached config. The persisted JWS (`config_v1.json.sig`) is re-verified over the
exact cached bytes on every load; a missing or invalid signature deletes both cache files
and falls through to the bundled seed. If no cache exists, the bundled seed config (if
present) is used. Flags return their code-provided default values if no config is
available at all.

**Migration note**: installs upgrading from a version without signature persistence have no
`config_v1.json.sig` alongside the cache. The first launch discards the existing cache and
falls back to the seed until the startup refresh restores a verified cache.

## JWS Signature Verification

The publisher writes two artifacts: `<app>/config.json` and `<app>/config.json.sig` (a
detached JWS, RFC 7797 `b64:false`, over the exact bytes of `config.json`). Clients check
for the compact JWS in the `x-bunting-signature` response header on the `config.json`
response first; if absent, they fetch `config.json.sig` from the same path. Raw S3/MinIO
serving with the `.sig` file is fully supported; CDN header injection is an optimization
that saves one request.

The SDK verifies the signature on every successful fetch:

1. Read the compact JWS from the `x-bunting-signature` response header; if absent, issue
   a GET to `<endpoint>.sig`.
2. Locate the matching public key by `kid` from the `public_keys` array in
   `BuntingConfig.plist`.
3. Verify the RS256 signature over the raw response bytes using `SecKeyVerifySignature`.
4. On success, persist the config bytes and JWS atomically. On failure, discard the
   response and retain the cache.

`ConfigSource` records where the active configuration came from: `.fetched` (fresh, verified
in this process), `.cache` (disk cache, re-verified on load), or `.seed` (bundled seed,
unverified at runtime). `signatureVerified` is `true` only for `.fetched` and `.cache`; the
seed's integrity story is verification at fetch time by `bunting-cli` plus the app bundle's
code signature.

Multiple public keys are supported to allow zero-downtime key rotation: publish with
both the old and new keys in the plist, rotate the signing key in the admin backend,
then remove the old key in a subsequent app release.

## Memoization

`MemoizationCache` is a thread-safe in-memory cache keyed by:

```
(flagKey, environment, contextHash, overridesVersion, configVersion)
```

`contextHash` is a stable hash of the `EvaluationContext` fields that affect condition
evaluation (platform, OS version, app version, locale, region). The cache is invalidated:

- Entirely: on config refresh, environment switch, or `clearAllOverrides()`
- Per-flag: on `setOverride(_:value:)` or `clearOverride(_:)`

Hot-path performance is <2µs for a cache hit; cold-path (miss + full evaluation) is
<100µs for typical flag configurations.

## Auto-Refresh

`Bunting` registers for foreground notifications:

- **iOS / tvOS**: `UIApplication.willEnterForegroundNotification`
- **macOS**: `NSApplication.willBecomeActiveNotification`

On each notification, `refresh()` is called. `ConfigStore` applies rate limiting, so
the CDN is not contacted more frequently than `min_interval_seconds`. This value is
required in `BuntingConfig.plist` (the SDK has no built-in fallback); the admin generates
the plist with a default of 21600 seconds (6 hours).
watchOS does not register a foreground observer; call `refresh()` manually if needed.

## Identity Management

`BuntingIdentity` stores a `UUID` in the device's iCloud Keychain:

- Scoped to the team ID by default; pass a `keychainAccessGroup` to share across apps.
- Survives app uninstall and reinstall (iCloud Keychain sync).
- Never transmitted to any server — used only for local bucketing.
- Can be reset via `resetIdentity()`, which generates a new UUID and invalidates the
  memoization cache (new identity may produce different bucket assignments).

## Override System

`OverridesStore` persists developer overrides to `UserDefaults`. Overrides take
priority over all evaluated variants and are intended for development and QA only.
They are surfaced in `BuntingDebugView`.

Override precedence: local override → evaluated variant → environment default.

## SwiftUI Integration

`Bunting` is `@Observable`, so SwiftUI views reading `Bunting.shared` properties
(e.g., `configuration`, `environment`) automatically re-render when they change.

Two built-in views are provided:

- `BuntingInfoView` — read-only: environment, config version, signature status, config source, device ID.
- `BuntingDebugView` — interactive: all of the above plus per-flag override controls.

The `@Environment(\.bunting)` key provides access to `Bunting.shared` through the
SwiftUI environment, avoiding prop drilling in large view hierarchies.
