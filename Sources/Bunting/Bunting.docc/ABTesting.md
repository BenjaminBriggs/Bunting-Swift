# A/B Testing with Bunting

Run experiments and measure feature impact with deterministic user bucketing.

## Overview

Bunting's test variants enable robust A/B testing with:
- **Deterministic bucketing** - Same user always gets same variant
- **Even distribution** - Consistent allocation across test groups
- **Device-based** - Users maintain assignment across app reinstalls (via Keychain)
- **Offline evaluation** - No network calls required during flag checks

## How Test Variants Work

Test variants use a deterministic bucketing algorithm:

1. **Hash** the user's device ID with a test-specific salt
2. **Map** the hash to a bucket number (1-100)
3. **Assign** the bucket to a test group based on percentage distribution
4. **Return** the value for that group

Because the device ID is stored in Keychain and syncs across devices (iCloud Keychain), the same user gets the same experience everywhere.

## Setting Up an A/B Test

### 1. Create a Test Definition

Define your test in the configuration:

```json
{
  "tests": {
    "onboarding_flow_test": {
      "salt": "onboarding_2024_q4",
      "groups": [
        {
          "name": "control",
          "percentage": 50
        },
        {
          "name": "variant_a",
          "percentage": 50
        }
      ],
      "conditions": []
    }
  }
}
```

**Key components:**
- `salt`: Unique identifier for this test (change it to re-randomize buckets)
- `groups`: Test groups with their percentage distribution
- `conditions`: Optional preconditions (e.g., "iOS 18+ only")

### 2. Create a Flag with Test Variant

Add a flag that references your test:

```json
{
  "flags": {
    "onboarding/flow_type": {
      "type": "string",
      "description": "Which onboarding flow to show",
      "production": {
        "default": "classic",
        "variants": [
          {
            "type": "test",
            "order": 1,
            "test": "onboarding_flow_test",
            "values": {
              "control": "classic_onboarding",
              "variant_a": "streamlined_onboarding"
            }
          }
        ]
      }
    }
  }
}
```

### 3. Access the Flag in Your App

Use the flag to control which experience users see:

```swift
let flowType = Bunting.shared.string("onboarding/flow_type", default: "classic")

switch flowType {
case "classic_onboarding":
    ClassicOnboardingFlow()
case "streamlined_onboarding":
    StreamlinedOnboardingFlow()
default:
    ClassicOnboardingFlow()
}
```

## Multivariate Testing (A/B/C/D)

Test multiple variants simultaneously:

```json
{
  "tests": {
    "paywall_design_test": {
      "salt": "paywall_2024_q4",
      "groups": [
        {"name": "control", "percentage": 25},
        {"name": "variant_a", "percentage": 25},
        {"name": "variant_b", "percentage": 25},
        {"name": "variant_c", "percentage": 25}
      ]
    }
  }
}
```

Flag configuration:

```json
{
  "type": "test",
  "order": 1,
  "test": "paywall_design_test",
  "values": {
    "control": "classic_paywall",
    "variant_a": "modern_paywall",
    "variant_b": "minimal_paywall",
    "variant_c": "premium_paywall"
  }
}
```

## Conditional Testing

Run tests only for specific audiences:

### iOS-Only Test

```json
{
  "tests": {
    "ios_widget_test": {
      "salt": "widget_2024",
      "groups": [
        {"name": "control", "percentage": 50},
        {"name": "with_widget", "percentage": 50}
      ],
      "conditions": [
        {
          "type": "platform",
          "operator": "in",
          "values": ["ios"]
        }
      ]
    }
  }
}
```

### New User Test

```json
{
  "tests": {
    "new_user_flow_test": {
      "salt": "new_users_2024",
      "groups": [
        {"name": "control", "percentage": 50},
        {"name": "variant", "percentage": 50}
      ],
      "conditions": [
        {
          "type": "custom_attribute",
          "operator": "custom",
          "values": ["new_user"]
        }
      ]
    }
  }
}
```

In your app configuration:

```swift
try Bunting.configure(
    environment: .production,
    customAttributes: { attribute in
        switch attribute {
        case "new_user":
            return UserDefaults.standard.bool(forKey: "isNewUser")
        default:
            return false
        }
    }
)
```

## Testing Best Practices

### 1. Use Meaningful Salts

Include the test purpose and time period in your salt:

```
✅ Good: "paywall_design_q4_2024"
✅ Good: "onboarding_flow_experiment_dec2024"
❌ Bad: "test1"
❌ Bad: "abc123"
```

### 2. Choose Appropriate Sample Sizes

Consider your traffic when setting percentages:

**Low traffic app (<10k DAU):**
```json
{"name": "control", "percentage": 50},
{"name": "variant", "percentage": 50}
```

**High traffic app (>100k DAU):**
```json
{"name": "control", "percentage": 10},
{"name": "variant", "percentage": 10},
{"name": "holdout", "percentage": 80}  // Not in test
```

### 3. Include Holdout Groups

For long-running tests, keep a group unexposed:

```json
{
  "groups": [
    {"name": "control", "percentage": 45},
    {"name": "variant", "percentage": 45},
    {"name": "holdout", "percentage": 10}
  ]
}
```

Handle the holdout:

```swift
let testGroup = Bunting.shared.string("experiment/test_group", default: "control")

if testGroup != "holdout" {
    // Show test experience
} else {
    // Show original experience (no test participation)
}
```

### 4. Test Locally with Overrides

Validate all variants work before deploying:

```swift
#if DEBUG
// Force specific variant for testing
Bunting.shared.setOverride("onboarding/flow_type", value: "variant_a")

// Test the variant...

// Clean up
Bunting.shared.clearOverride("onboarding/flow_type")
#endif
```

### 5. Document Your Hypotheses

Use flag descriptions to document what you're testing:

```json
{
  "description": "H0: Streamlined onboarding increases completion rate by 10%. Testing: Dec 2024. Owner: @product-team"
}
```

## Tracking and Analytics

### Log Test Assignments

Track which variant each user received:

```swift
let variant = Bunting.shared.string("onboarding/flow_type", default: "control")

// Log to your analytics
Analytics.log(event: "test_assignment", properties: [
    "test_name": "onboarding_flow_test",
    "variant": variant,
    "user_id": currentUserID
])
```

### Use BuntingEventsDelegate

Monitor test evaluations in real-time:

```swift
class AnalyticsDelegate: BuntingEventsDelegate {
    func didEvaluateFlag(key: String, value: Any) {
        // Track every flag evaluation
        Analytics.log("flag_evaluated", ["key": key, "value": value])
    }
}

Bunting.shared.eventsDelegate = AnalyticsDelegate()
```

## Stopping Tests

### Declare a Winner

Once you have statistical significance:

1. Remove the test variant from the configuration
2. Update the default value to the winning variant
3. Deploy the new configuration

**Before:**
```json
{
  "default": "classic",
  "variants": [
    {
      "type": "test",
      "test": "onboarding_test",
      "values": {"control": "classic", "variant": "streamlined"}
    }
  ]
}
```

**After (variant won):**
```json
{
  "default": "streamlined",
  "variants": []
}
```

### Gradual Winner Rollout

If you want to validate the winner before 100%:

```json
{
  "default": "classic",
  "variants": [
    {
      "order": 1,
      "type": "rollout",
      "value": "streamlined",
      "rollout": "winner_rollout"
    }
  ]
}
```

## Common Patterns

### Sequential Testing

Test feature A, then use winners in test B:

```swift
// Test 1: Onboarding flow
let onboardingFlow = Bunting.shared.string("test/onboarding", default: "classic")

// Test 2: Paywall timing (only for users who completed onboarding)
if userCompletedOnboarding {
    let paywallTiming = Bunting.shared.string("test/paywall_timing", default: "immediate")
}
```

### Nested Tests

Run different tests based on platform:

```json
{
  "ios_checkout_test": {
    "conditions": [
      {
        "type": "platform",
        "operator": "in",
        "values": ["ios"]
      }
    ]
  }
}
```

Note: this SDK only ever runs on Apple platforms, so `EvaluationContext.current()` never reports anything but `ios`, `macos`, `watchos`, `tvos`, or `visionos`. The `platform` condition's value space is broader (`android`, `web`, etc. are valid wire values for the admin's cross-platform targeting model), but conditions targeting non-Apple platforms simply never match from this SDK.

### Test + Killswitch

Combine a test with a killswitch for safety:

```json
{
  "variants": [
    {
      "order": 1,
      "type": "conditional",
      "value": "disabled",
      "conditions": [
        {
          "type": "custom_attribute",
          "operator": "custom",
          "values": ["test_killed"]
        }
      ]
    },
    {
      "order": 2,
      "type": "test",
      "test": "main_test",
      "values": {"control": "v1", "variant": "v2"}
    }
  ]
}
```

## See Also

- <doc:UnderstandingVariants> - How variants work
- <doc:GradualRollouts> - Percentage-based deployment
- ``Test`` - API reference for test definitions
- ``Bunting/setOverride(_:value:)`` - Testing variants locally
