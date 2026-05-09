# Entitlement Mapping

How RevenueCat's `CustomerInfo.entitlements` translates to Swidux's `EntitlementSnapshot`.

## Overview

`RevenueCatPaywallService` exists to do one thing: turn a `RevenueCat.CustomerInfo` into an `EntitlementSnapshot` the paywall plugin can consume. The mapping is small, deterministic, and ID-driven. This article spells it out so you can predict — without reading the source — what flag values a given dashboard configuration produces.

## The mapping rule

For every `CustomerInfo` the service receives, two flags are computed:

```
isPro              = entitlements[entitlementID]?.isActive == true
hasPermanentLicense = permanentLicenseEntitlementID
                       .flatMap { entitlements[$0]?.isActive } == true
```

In prose:

- A flag is `true` only if the relevant identifier was configured **and** the entitlement at that identifier is present **and** active.
- Missing entitlements behave identically to inactive entitlements. `nil` is never a third state.
- The permanent-license identifier is independent. If it is `nil`, `hasPermanentLicense` is always `false` regardless of what's in `CustomerInfo.entitlements`.

## Truth table

| Configuration | `entitlements["pro"]?.isActive` | `entitlements["lifetime"]?.isActive` | Result |
|---|---|---|---|
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: nil` | `true` | (any) | `isPro = true`, `hasPermanentLicense = false` |
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: nil` | `false` or absent | (any) | `isPro = false`, `hasPermanentLicense = false` |
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: "lifetime"` | `false` or absent | `true` | `isPro = false`, `hasPermanentLicense = true` |
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: "lifetime"` | `true` | `true` | `isPro = true`, `hasPermanentLicense = true` |
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: "lifetime"` | `false` or absent | `false` or absent | `isPro = false`, `hasPermanentLicense = false` |
| `entitlementID: "pro"`, `permanentLicenseEntitlementID: "lifetime"` | `true` | `false` or absent | `isPro = true`, `hasPermanentLicense = false` |

Every row above maps to a test case in `RevenueCatPaywallServiceTests` — the mapping is the package's contract.

## Why missing == inactive

Treating "absent" the same as "inactive" simplifies the mental model: feature code never has to handle a third state where the gate is "indeterminate." A missing entitlement always denies access. This matches what users expect — a user who never bought the SKU sees the paywall, the same as a user whose subscription lapsed.

The cost is that a misconfigured dashboard (entitlement renamed, identifier typo in your service init) silently denies access rather than throwing. Catch this with an integration test that asserts the live service produces an active entitlement for a known sandbox account, or with a launch-time sanity log when `isPro` stays `false` longer than expected.

## Why two flags instead of one

The plugin could expose a single `isEntitled` flag. It exposes two so UI can branch on the *source* of entitlement:

- A subscriber sees a *Manage Subscription* button leading to the customer center.
- A lifetime user sees no manage button — there's nothing to manage on a one-time purchase.
- Marketing copy can thank lifetime users explicitly without having to check the underlying SKU.

`PaywallState.isGateSatisfied` is `isPro || hasPermanentLicense`. Feature gating uses that single read; UI personalization branches on the underlying flags.

## Stream semantics

The mapping rule applies identically whether the snapshot comes from `customerInfo()`, `customerInfoStream()`, or `restorePurchases()`. The service does not preserve any state across calls — every snapshot is computed afresh from the `CustomerInfo` in hand. This means:

- Two consecutive identical `CustomerInfo` values produce two identical snapshots. The plugin's `.customerInfoUpdated` reducer no-ops cleanly when the snapshot is unchanged.
- A subscription expiring server-side surfaces as a snapshot with `isPro = false` on the next stream yield. Your gate flips closed automatically.
- A restore that recovers a lifetime purchase surfaces as `hasPermanentLicense = true` on the next call, even if the user's subscription was never restored.

## See Also

- <doc:ServiceReference>
- <doc:HowToImplementService>
- <doc:HowToAddAPermanentLicense>
