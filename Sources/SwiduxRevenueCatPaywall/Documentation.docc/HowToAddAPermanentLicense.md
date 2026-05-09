# How to Add a Permanent License

Sell a lifetime entitlement alongside a subscription and surface both flags through the paywall plugin.

## Overview

Many apps offer two ways to buy: a recurring pro subscription and a one-time lifetime purchase. RevenueCat models both as entitlements; `RevenueCatPaywallService` checks each independently and surfaces them as the two flags on `EntitlementSnapshot`:

- `isPro` — active subscription.
- `hasPermanentLicense` — active lifetime entitlement.

The paywall plugin's `isGateSatisfied` is `isPro || hasPermanentLicense`, so feature code keeps a single check while UI can branch on the underlying flags when it needs to.

For the entitlement-mapping rules and edge cases, see <doc:EntitlementMapping>.

## Before you start

This guide assumes:

- You have completed <doc:HowToImplementService>.
- You have configured **two** entitlements in the RevenueCat dashboard — typically `pro` for the subscription and `lifetime` for the one-time purchase. The identifiers are arbitrary; only the strings need to match what you pass into the service.

## Step 1: Pass the second identifier

Replace the single-entitlement init with the two-arg form:

```swift
import SwiduxRevenueCatPaywall

let service = RevenueCatPaywallService(
    entitlementID: "pro",
    permanentLicenseEntitlementID: "lifetime"
)
```

Both entitlements are now checked on every `customerInfo()`, `customerInfoStream()` yield, and `restorePurchases()` call. The active state of `pro` flows into `EntitlementSnapshot.isPro`; the active state of `lifetime` flows into `hasPermanentLicense`.

The two flags are independent. A user with both active gets both flags set; a user with only one active gets only that flag set.

## Step 2: Wire the service into the plugin

Same as the single-entitlement case — the plugin doesn't need to know about the second identifier:

```swift
plugins.register(
    PaywallPlugin<AppState, AppAction>(
        state: \.paywall,
        action: AppAction.paywall,
        extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
        service: RevenueCatPaywallService(
            entitlementID: "pro",
            permanentLicenseEntitlementID: "lifetime"
        )
    )
)
```

## Step 3: Decide whether feature code needs to branch

For most gated features, keep using `store.paywall.isGateSatisfied`:

```swift
if store.paywall.isGateSatisfied { … }
```

This stays correct whether the user has a subscription or a lifetime license, and works identically in apps that don't sell a lifetime SKU.

## Step 4: Branch in UI when copy must differ

If the paywall sheet should be hidden for lifetime customers (so they're not pestered to subscribe), or if the customer-center entry should be relabeled, branch on the underlying flag:

```swift
if store.paywall.hasPermanentLicense {
    Text("Lifetime member — thank you!")
} else if store.paywall.isPro {
    Button("Manage Subscription") {
        store.send(.paywall(.presentCustomerCenter))
    }
} else {
    Button("Upgrade") {
        store.send(.paywall(.request(reason: "upgrade-prompt")))
    }
}
```

Lifetime users typically have nothing to manage in App Store / Settings. Hiding the customer-center button for them avoids dead-end taps.

## When to skip the second identifier

Pass `nil` (or omit the parameter) if your app has no lifetime SKU:

```swift
RevenueCatPaywallService(entitlementID: "pro")
```

`hasPermanentLicense` then stays `false` regardless of any entitlements RevenueCat reports — even if the dashboard accidentally has a `lifetime` entitlement that the service is not configured to check. See the *Lifetime entitlement is ignored when no permanent-license ID is configured* test case for the precise behavior.

## See Also

- <doc:ServiceReference>
- <doc:EntitlementMapping>
- <doc:HowToImplementService>
