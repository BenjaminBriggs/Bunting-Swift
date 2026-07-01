# Gradual Rollouts

Deploy features safely with percentage-based rollouts and monitor impact incrementally.

## Overview

Gradual rollouts let you deploy features to an increasing percentage of users over time. This approach:

- **Reduces risk** - Catch issues early before full deployment
- **Validates performance** - Monitor system load incrementally
- **Enables quick rollback** - Disable features instantly if problems arise
- **Builds confidence** - Increase percentage as metrics look good

Bunting's rollout variants use deterministic bucketing, so the same users always qualify as you increase percentages.

## How Rollouts Work

Rollout bucketing is deterministic and stable:

1. **Hash** the user's device ID with the rollout's salt
2. **Map** the hash to a bucket (1-100)
3. **Compare** bucket to rollout percentage
4. **Return** value if bucket ≤ percentage

**Key property:** Users with buckets 1-10 will always be in a 10% rollout, 25% rollout, 50% rollout, etc. This ensures stable user groups as you increase percentages.

## Basic Rollout Setup

### 1. Create a Rollout Definition

```json
{
  "rollouts": {
    "new_search_engine": {
      "salt": "search_v2_2024",
      "percentage": 10,
      "conditions": []
    }
  }
}
```

**Components:**
- `salt`: Unique identifier (change to re-randomize buckets)
- `percentage`: 1-100, percentage of users who qualify
- `conditions`: Optional preconditions (platform, version, etc.)

### 2. Create a Flag with Rollout Variant

```json
{
  "flags": {
    "search/engine_version": {
      "type": "string",
      "description": "Which search engine to use",
      "production": {
        "default": "v1",
        "variants": [
          {
            "type": "rollout",
            "order": 1,
            "value": "v2",
            "rollout": "new_search_engine"
          }
        ]
      }
    }
  }
}
```

### 3. Access the Flag

```swift
let engineVersion = Bunting.shared.string("search/engine_version", default: "v1")

switch engineVersion {
case "v1":
    return LegacySearchEngine()
case "v2":
    return NewSearchEngine()
default:
    return LegacySearchEngine()
}
```

## Rollout Strategy

### The 1-5-25-50-100 Strategy

A common safe rollout progression:

**Day 1: 1% rollout**
```json
{"percentage": 1}
```
- Validate basic functionality
- Check for crashes or critical bugs
- Monitor error rates

**Day 3: 5% rollout**
```json
{"percentage": 5}
```
- Confirm metrics are stable
- Check performance under higher load
- Gather initial user feedback

**Week 1: 25% rollout**
```json
{"percentage": 25}
```
- Validate at meaningful scale
- Check for edge cases
- Monitor backend performance

**Week 2: 50% rollout**
```json
{"percentage": 50}
```
- Half of users on new feature
- Compare metrics between groups
- Final validation before full rollout

**Week 3: 100% rollout**
```json
{"percentage": 100}
```
- Everyone gets the new feature
- Monitor for universal adoption issues

### Aggressive Rollout (Low-Risk Features)

For low-risk features or UI changes:

```
Day 1: 10%
Day 2: 50%
Day 3: 100%
```

### Conservative Rollout (High-Risk Features)

For critical features or infrastructure changes:

```
Day 1: 0.1%
Day 3: 1%
Week 1: 5%
Week 2: 10%
Week 3: 25%
Week 4: 50%
Week 5: 75%
Week 6: 100%
```

## Conditional Rollouts

### Platform-Specific Rollout

Roll out to iOS first, then other platforms:

```json
{
  "rollouts": {
    "ios_rollout": {
      "salt": "feature_ios_2024",
      "percentage": 50,
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["iOS"]
        }
      ]
    },
    "macos_rollout": {
      "salt": "feature_macos_2024",
      "percentage": 10,
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["macOS"]
        }
      ]
    }
  }
}
```

### Version-Gated Rollout

Deploy to newer app versions first:

```json
{
  "rollouts": {
    "modern_versions_rollout": {
      "salt": "feature_2024",
      "percentage": 50,
      "conditions": [
        {
          "type": "app_version",
          "operator": "greater_than_or_equal",
          "values": ["2.0.0"]
        }
      ]
    }
  }
}
```

### Region-Based Rollout

Test in specific markets first:

```json
{
  "rollouts": {
    "us_rollout": {
      "salt": "feature_us_2024",
      "percentage": 100,
      "conditions": [
        {
          "type": "region",
          "operator": "in",
          "values": ["US"]
        }
      ]
    },
    "global_rollout": {
      "salt": "feature_global_2024",
      "percentage": 10
    }
  }
}
```

Flag configuration:

```json
{
  "variants": [
    {
      "order": 1,
      "type": "rollout",
      "value": true,
      "rollout": "us_rollout"
    },
    {
      "order": 2,
      "type": "rollout",
      "value": true,
      "rollout": "global_rollout"
    }
  ]
}
```

## Monitoring Rollouts

### Track Rollout Exposure

Log when users are exposed to rolled-out features:

```swift
let isNewFeatureEnabled = Bunting.shared.bool("feature/new_ui", default: false)

if isNewFeatureEnabled {
    Analytics.log("feature_rollout_exposure", [
        "feature": "new_ui",
        "rollout_percentage": getCurrentRolloutPercentage()
    ])
}
```

### Use Events Delegate

Monitor all flag evaluations:

```swift
class RolloutMonitor: BuntingEventsDelegate {
    func didEvaluateFlag(key: String, value: Any) {
        if key.contains("rollout") {
            Metrics.increment("rollout_evaluation", tags: ["flag": key])
        }
    }
    
    func didFetchConfiguration(version: String) {
        Logger.info("New config fetched: \(version)")
        // Alert your team that a new rollout percentage is active
    }
}
```

### Track Metrics by Group

Compare metrics between rolled-out and control groups:

```swift
let hasNewFeature = Bunting.shared.bool("feature/new_checkout", default: false)

Analytics.setUserProperty("checkout_version", value: hasNewFeature ? "v2" : "v1")

// Track conversion rates split by group
Analytics.log("checkout_completed", properties: [
    "version": hasNewFeature ? "v2" : "v1",
    "revenue": purchaseAmount
])
```

## Rollback Strategies

### Instant Rollback

Set percentage to 0:

```json
{
  "rollouts": {
    "problematic_feature": {
      "salt": "feature_2024",
      "percentage": 0  // Disable immediately
    }
  }
}
```

### Gradual Rollback

Reduce percentage incrementally:

```
Current: 50%
Hour 1: 25%
Hour 2: 10%
Hour 3: 0%
```

### Conditional Rollback

Disable for specific platforms while investigating:

```json
{
  "variants": [
    {
      "order": 1,
      "type": "conditional",
      "value": false,
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["iOS"]
        }
      ]
    },
    {
      "order": 2,
      "type": "rollout",
      "value": true,
      "rollout": "feature_rollout"
    }
  ]
}
```

This disables the feature for all iOS users while keeping the rollout active for other platforms.

## Common Patterns

### Beta Users + Gradual Rollout

Give beta users early access, then roll out to everyone:

```json
{
  "variants": [
    {
      "order": 1,
      "type": "conditional",
      "value": true,
      "conditions": [
        {
          "type": "custom_attribute",
          "operator": "custom",
          "values": ["beta_tester"]
        }
      ]
    },
    {
      "order": 2,
      "type": "rollout",
      "value": true,
      "rollout": "main_rollout"
    }
  ]
}
```

### Staged Rollout by Platform

Roll out to each platform at different speeds:

```json
{
  "variants": [
    {
      "order": 1,
      "type": "rollout",
      "value": true,
      "rollout": "ios_rollout",
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["iOS"]
        }
      ]
    },
    {
      "order": 2,
      "type": "rollout",
      "value": true,
      "rollout": "macos_rollout",
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["macOS"]
        }
      ]
    }
  ]
}
```

Update each rollout's percentage independently.

### Canary Rollout

Keep a small percentage as canary, then jump to 100%:

```
Day 1: 5% (canary)
Day 7: 5% (monitor for a week)
Day 8: 100% (if metrics good)
```

### Progressive Feature Rollout

Roll out features in stages:

```swift
let rolloutStage = Bunting.shared.int("feature/stage", default: 0)

switch rolloutStage {
case 1:
    // Stage 1: Basic functionality (10% of users)
    showBasicFeature()
case 2:
    // Stage 2: Advanced features (25% of users)
    showAdvancedFeature()
case 3:
    // Stage 3: Full feature set (50% of users)
    showFullFeature()
default:
    // No feature (remaining users)
    showLegacyExperience()
}
```

## Best Practices

### 1. Use Descriptive Salts

Include feature name and time period:

```
✅ Good: "new_paywall_rollout_q4_2024"
✅ Good: "search_v2_gradual_december_2024"
❌ Bad: "rollout1"
❌ Bad: "test"
```

### 2. Set Alerts

Monitor key metrics during rollouts:

- Error rates
- Crash rates
- Performance metrics
- User engagement
- Conversion rates

Set up alerts to trigger if metrics degrade.

### 3. Document Rollout Plans

Use flag descriptions:

```json
{
  "description": "Rollout plan: 1% (12/1), 5% (12/3), 25% (12/7), 50% (12/10), 100% (12/15). Owner: @eng-team"
}
```

### 4. Test Locally

Validate both rollout states:

```swift
#if DEBUG
// Test enabled state
Bunting.shared.setOverride("feature/new_ui", value: true)
// ... validate UI ...

// Test disabled state  
Bunting.shared.setOverride("feature/new_ui", value: false)
// ... validate fallback ...

Bunting.shared.clearAllOverrides()
#endif
```

### 5. Keep Old Code

Don't delete the old implementation until 100% rollout is stable:

```swift
let useNewImplementation = Bunting.shared.bool("feature/new_algo", default: false)

if useNewImplementation {
    return newAlgorithm.calculate()
} else {
    return legacyAlgorithm.calculate()  // Keep this until rollout complete
}
```

## Rollout Checklist

Before starting a rollout:

- [ ] Set up monitoring and alerts
- [ ] Document rollout plan and schedule
- [ ] Test both enabled and disabled states
- [ ] Identify rollback triggers (error rate, crash rate, etc.)
- [ ] Communicate rollout schedule to team
- [ ] Set up analytics tracking for group comparison
- [ ] Have on-call engineer ready during initial rollout

During rollout:

- [ ] Monitor metrics at each percentage
- [ ] Wait sufficient time at each stage (at least 24-48 hours)
- [ ] Check for statistically significant issues
- [ ] Document any issues encountered
- [ ] Be ready to rollback if needed

After rollout:

- [ ] Validate 100% rollout is stable
- [ ] Remove old code after 1-2 weeks
- [ ] Update documentation
- [ ] Clean up rollout configuration (remove variant, update default)

## See Also

- <doc:UnderstandingVariants> - How variants work
- <doc:ABTesting> - Running experiments with test variants
- ``Rollout`` - API reference for rollout definitions
- ``Bunting/refresh()`` - Manually refresh configuration for faster rollout updates
