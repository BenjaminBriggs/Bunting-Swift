# Changelog

All notable changes to the Bunting Swift SDK are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `visionOS` is now correctly detected as the device platform. Previously `EvaluationContext.current()` had no `visionOS` branch, so Vision Pro devices reported platform `"unknown"` and `platform` conditions targeting `"visionOS"` never matched.
- `BuntingInfoView` and `BuntingDebugView` now show the last successful fetch time and the cached ETag instead of blank placeholders.
- Substantially expanded automated test coverage: the flag evaluator, memoization cache, overrides store, config store (transport, caching, fallback), JWS signature verification, config decoding, codegen output, and the `bunting-cli`/`bunting-codegen` executables all now have dedicated test suites.

### Changed

- JWS signature verification now strictly validates the protected header before trusting it: `alg` must be `RS256`, `b64` must be `false`, and `crit` must be exactly `["b64"]`. A signature with an unexpected algorithm or an unrecognized `crit` extension is now rejected instead of being evaluated as if it used the documented scheme.
- The config artifact's `schema_version` is now validated. An artifact with an unsupported `schema_version` is rejected outright and triggers the normal cache/seed fallback, instead of being silently mis-decoded.

### Fixed

- Date flag values with fractional seconds — the format actually published by the admin backend, e.g. `"2026-07-01T10:00:04.796Z"` — now decode correctly. Previously they failed ISO 8601 parsing and `date(key:default:)` silently returned the caller-supplied default.
- Double-typed flags whose value is a whole number (e.g. `2.0`, which serializes as `2` in JSON) now resolve to the correct value instead of falling back to the caller-supplied default.
- The codegen plugin now emits a `Double` literal (e.g. `2.0`) for whole-number double flag defaults instead of incorrectly coercing them to `0.0`.
