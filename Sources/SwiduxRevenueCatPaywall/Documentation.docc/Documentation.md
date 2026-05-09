# ``SwiduxRevenueCatPaywall``

RevenueCat adapter for Swidux's `PaywallPlugin`. Implements `PaywallService` against `Purchases.shared`, ships a controllable mock for previews and tests, and pairs with `SwiduxRevenueCatPaywallUI` for drop-in `PaywallView` and `CustomerCenterView` presentation.

@Metadata {
    @DisplayName("SwiduxRevenueCatPaywall")
}

## Overview

`SwiduxRevenueCatPaywall` is the adapter between RevenueCat's SDK and Swidux's purchase-agnostic paywall plugin. The plugin owns paywall state (presentation flags, current entitlement, async progress); this package translates RevenueCat's `CustomerInfo` into the `EntitlementSnapshot` the plugin expects, and surfaces the live `customerInfoStream` so entitlement changes propagate without polling.

Two products ship together:

- **`SwiduxRevenueCatPaywall`** — `RevenueCatPaywallService` (the live `PaywallService` conformer) and `MockRevenueCatPaywallService` (a controllable preview / test conformer).
- **`SwiduxRevenueCatPaywallUI`** — `PaywallSheet` and `CustomerCenterSheet`, drop-in SwiftUI views that wrap RevenueCatUI with platform-aware presentation, plus a `revenueCatPaywall(state:send:)` view modifier that composes both.

The flow:

```
View → store.send(.paywall(.request(reason:)))
  → PaywallPlugin sets isPresented = true
  → PaywallSheet observes the change, presents RevenueCatUI.PaywallView
  → user purchases → Purchases.shared.customerInfoStream yields a new CustomerInfo
  → RevenueCatPaywallService maps it to EntitlementSnapshot
  → PaywallPlugin reduces .customerInfoUpdated, sets isPro = true
  → store.paywall.isGateSatisfied flips, gated UI unlocks
```

The plugin and the adapter stay decoupled: the plugin doesn't know about RevenueCat, and the adapter doesn't know about your action tree.

## Topics

### Quickstart

- <doc:GettingStarted>

### How-to Guides

- <doc:HowToImplementService>
- <doc:HowToAddAPermanentLicense>
- <doc:HowToPresentTheUI>
- <doc:HowToPreviewAndTest>

### Reference

- <doc:ServiceReference>
- <doc:MockServiceReference>
- <doc:UIComponentsReference>

### Explanation

- <doc:PlatformBehavior>
- <doc:EntitlementMapping>

### Service Layer

- ``RevenueCatPaywallService``

### Testing

- ``MockRevenueCatPaywallService``
