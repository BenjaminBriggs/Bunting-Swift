# ``Bunting``

A self-hosted, offline-first feature flag system for Apple platforms with strong typing and cryptographic security.

## Overview

Bunting is a feature flag SDK designed for Apple platforms (iOS, macOS, watchOS, tvOS) that prioritizes security, performance, and developer experience. Unlike cloud-based solutions, Bunting is:

- **Self-hosted**: You control your feature flag infrastructure
- **Offline-first**: Flags work without network connectivity
- **Cryptographically secure**: All configs are signed with JWS signatures
- **Strongly typed**: Codegen plugin generates type-safe flag accessors
- **High-performance**: Sub-microsecond cache hits for flag evaluation

### Key Features

- **Synchronous API** - No async/await needed for flag access
- **Signature Verification** - Offline verification of flag configs using embedded public keys
- **A/B Testing** - Deterministic user bucketing for experiments
- **Gradual Rollouts** - Percentage-based feature deployment
- **Debug Tools** - Built-in SwiftUI views for testing and debugging
- **Memoization** - Automatic caching of evaluation results
- **Observable** - SwiftUI integration with @Observable support

## Topics

### Essentials

- <doc:GettingStarted>
- ``Bunting/Bunting``
- ``BuntingEnvironment``
- ``EvaluationContext``

### Flag Access

- ``Bunting/bool(_:default:)``
- ``Bunting/string(_:default:)``
- ``Bunting/int(_:default:)``
- ``Bunting/double(_:default:)``
- ``Bunting/date(_:default:)``
- ``Bunting/jsonData(_:)``

### Configuration & Setup

- ``Bunting/configure(environment:context:keychainAccessGroup:customAttributes:)``
- ``Bunting/shared``
- ``Bunting/refresh()``
- ``Bunting/setEnvironment(_:)``

### Testing & Debugging

- ``Bunting/setOverride(_:value:)``
- ``Bunting/clearOverride(_:)``
- ``Bunting/clearAllOverrides()``
- ``Bunting/getAllOverrides()``
- ``BuntingDebugView``
- ``BuntingInfoView``

### Understanding Variants

- <doc:UnderstandingVariants>
- ``Variant``
- ``VariantType``
- ``Condition``

### Configuration Models

- ``BuntingConfiguration``
- ``Flag``
- ``EnvironmentConfig``
- ``FlagValue``
- ``FlagType``

### Advanced Features

- <doc:ABTesting>
- <doc:GradualRollouts>
- ``Test``
- ``Rollout``
- ``Cohort``

### Events & Observability

- ``BuntingEventsDelegate``
- ``Bunting/eventsDelegate``

### Identity & Security

- ``Bunting/localID``
- ``Bunting/resetIdentity()``
- ``Bunting/cachedLocalID``
