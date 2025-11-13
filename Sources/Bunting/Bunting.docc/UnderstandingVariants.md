# Understanding Variants

Learn how Bunting evaluates feature flags using ordered variants.

## Overview

Variants are the core mechanism that determines which value a flag returns. Each flag can have multiple variants per environment, and they're evaluated in order until one matches. This powerful system enables:

- **Conditional features** - Show features only to specific users or platforms
- **A/B testing** - Assign users to different test groups
- **Gradual rollouts** - Deploy features to a percentage of users
- **Contextual behavior** - Different values for iOS vs macOS, or different app versions

## How Variants Work

When you access a flag, Bunting evaluates variants in this order:

1. **Check for override** - Developer overrides always win (for testing)
2. **Check cache** - Return cached value if available (<2µs)
3. **Evaluate variants** - Process variants in ascending order by their `order` property
4. **Return default** - If no variant matches, return the environment's default value

The first variant whose conditions match is returned immediately. No further variants are considered.

## The Three Variant Types

### Conditional Variants

Conditional variants return a value when all their conditions evaluate to true.

**Use cases:**
- Platform-specific features (iOS-only, macOS-only)
- Version gating (iOS 18+, app version 2.0+)
- Region-specific features (US-only, EU-only)
- Cohort targeting (beta users, pro subscribers)

**Example:**
```json
{
  "type": "conditional",
  "order": 1,
  "value": true,
  "conditions": [
    {
      "attribute": "platform",
      "operator": "equals",
      "value": "iOS"
    },
    {
      "attribute": "os_version",
      "operator": "greater_than_or_equal",
      "value": "18.0"
    }
  ]
}
```

This variant returns `true` only for iOS 18+ users.

### Test Variants

Test variants deterministically bucket users into groups for A/B testing.

**Use cases:**
- A/B testing different designs or features
- Multivariate testing (A/B/C/D tests)
- Consistent user experience (same user always gets same variant)

**How bucketing works:**
1. Hash the user's device ID with the test's salt
2. Map the hash to a bucket (1-100)
3. Assign bucket to a test group based on distribution
4. Return the value for that group

**Example:**
```json
{
  "type": "test",
  "order": 1,
  "test": "paywall_design_test",
  "values": {
    "control": "classic_paywall",
    "variant_a": "new_paywall_v1",
    "variant_b": "new_paywall_v2"
  }
}
```

With a test definition:
```json
{
  "salt": "paywall_2024_q1",
  "groups": [
    {"name": "control", "percentage": 34},
    {"name": "variant_a", "percentage": 33},
    {"name": "variant_b", "percentage": 33}
  ]
}
```

Users are deterministically split into three groups, ensuring consistent experiences.

### Rollout Variants

Rollout variants gradually deploy features to a percentage of users.

**Use cases:**
- Gradual feature deployment (1% → 5% → 25% → 100%)
- Risk mitigation (detect issues early before full rollout)
- Performance testing (validate infrastructure under load)
- Beta features (10% of users get early access)

**How rollouts work:**
1. Hash the user's device ID with the rollout's salt
2. Map the hash to a bucket (1-100)
3. Return value if bucket ≤ rollout percentage

**Example:**
```json
{
  "type": "rollout",
  "order": 1,
  "value": true,
  "rollout": "new_feature_rollout"
}
```

With a rollout definition:
```json
{
  "salt": "new_feature_2024",
  "percentage": 10
}
```

Only 10% of users (deterministically selected) will see the new feature.

## Evaluation Order Matters

Variants are sorted by their `order` property (ascending) before evaluation. Lower order values are evaluated first.

**Example: Progressive targeting**

```json
[
  {
    "order": 1,
    "type": "conditional",
    "value": true,
    "conditions": [{"attribute": "cohort", "value": "beta_users"}]
  },
  {
    "order": 2,
    "type": "rollout",
    "value": true,
    "rollout": "gradual_rollout"
  }
]
```

This configuration:
1. First checks if user is in `beta_users` cohort → returns `true`
2. If not, checks if user qualifies for 10% rollout → returns `true` if yes
3. If neither matches → returns the environment's default value

## Combining Variants with Conditions

All variant types can have additional conditions. The variant only matches if:
1. The variant-specific logic passes (test group, rollout percentage, etc.)
2. ALL conditions are true

**Example: iOS-only gradual rollout**

```json
{
  "type": "rollout",
  "order": 1,
  "value": true,
  "rollout": "ios_rollout",
  "conditions": [
    {
      "attribute": "platform",
      "operator": "equals",
      "value": "iOS"
    }
  ]
}
```

This rollout only applies to iOS users who also qualify for the percentage-based rollout.

## Common Patterns

### Feature Flag with Escape Hatch

Enable a feature for a percentage of users, but allow beta testers to always access it:

```json
[
  {
    "order": 1,
    "type": "conditional",
    "value": true,
    "conditions": [{"attribute": "custom", "value": "beta_tester"}]
  },
  {
    "order": 2,
    "type": "rollout",
    "value": true,
    "rollout": "main_rollout"
  }
]
```

### Platform-Specific A/B Test

Run an A/B test only on iOS:

```json
[
  {
    "order": 1,
    "type": "test",
    "test": "ios_design_test",
    "values": {
      "control": "old_design",
      "variant": "new_design"
    },
    "conditions": [
      {"attribute": "platform", "operator": "equals", "value": "iOS"}
    ]
  }
]
```

### Staged Rollout by Version

Roll out to newer app versions first:

```json
[
  {
    "order": 1,
    "type": "conditional",
    "value": true,
    "conditions": [
      {"attribute": "app_version", "operator": "greater_than_or_equal", "value": "2.0.0"}
    ]
  },
  {
    "order": 2,
    "type": "rollout",
    "value": true,
    "rollout": "legacy_version_rollout"
  }
]
```

## Best Practices

1. **Keep order simple** - Use increments of 10 (10, 20, 30) to leave room for insertion
2. **Limit variants** - More than 5 variants per flag becomes hard to reason about
3. **Document intent** - Use clear flag descriptions to explain variant logic
4. **Test locally** - Use overrides to test each variant path
5. **Monitor metrics** - Track which variants are matching in production

## See Also

- <doc:ABTesting> - Deep dive into running experiments
- <doc:GradualRollouts> - Strategies for safe feature deployment
- ``Variant`` - API reference for variant structure
- ``Condition`` - Available condition types and operators
