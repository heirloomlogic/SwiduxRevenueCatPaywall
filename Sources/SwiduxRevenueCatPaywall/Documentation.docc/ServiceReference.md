# Service Reference

API reference for `RevenueCatPaywallService` — the RevenueCat-backed `PaywallService` conformer that the paywall plugin consumes.

## Overview

`RevenueCatPaywallService` adapts `RevenueCat.Purchases` to the `PaywallService` protocol that `SwiduxPaywall.PaywallPlugin` requires. It does one job: translate `CustomerInfo` into `EntitlementSnapshot` (defined by `SwiduxPaywall`) so the plugin can drive its state. Configuration of the RevenueCat SDK itself remains the caller's responsibility.

For a step-by-step integration walkthrough, see <doc:HowToImplementService>. For the entitlement-mapping rules, see <doc:EntitlementMapping>.

## Library target

- Product: `SwiduxRevenueCatPaywall`
- Import: `import SwiduxRevenueCatPaywall`

`Package.swift`:

```swift
.product(name: "SwiduxRevenueCatPaywall", package: "SwiduxRevenueCatPaywall"),
```

## Types

### ``RevenueCatPaywallService``

```swift
public struct RevenueCatPaywallService: PaywallService {
    public init(
        entitlementID: String,
        permanentLicenseEntitlementID: String? = nil
    )

    public func customerInfo() async throws -> EntitlementSnapshot
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot>
    public func restorePurchases() async throws -> EntitlementSnapshot
}
```

Value type. Holds two `String` identifiers and forwards every call to `Purchases.shared`. Cheap to construct and pass into `PaywallPlugin` — after `RevenueCatPaywall.configure` has run. For production, wrap it in SwiduxPaywall's `ResilientPaywallService` so a transient read failure at launch never gates a paid user as free.

#### Initializer

```swift
public init(
    entitlementID: String,
    permanentLicenseEntitlementID: String? = nil
)
```

- `entitlementID` — RevenueCat entitlement identifier that grants pro access. Surfaces as `EntitlementSnapshot.isPro` when active.
- `permanentLicenseEntitlementID` — Optional secondary identifier for a lifetime / permanent entitlement. Surfaces as `EntitlementSnapshot.hasPermanentLicense` when active. Pass `nil` if the app has no separate lifetime SKU.

> Important: Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` before constructing the service. The initializer preconditions on the SDK being configured — failing fast with a named fix instead of letting `Purchases.shared` trap opaquely at first use. Previews and tests should construct `MockRevenueCatPaywallService` instead.

#### `customerInfo() async throws -> EntitlementSnapshot`

One-shot fetch. Calls `Purchases.shared.customerInfo()` and maps the result.

Throws whatever the RevenueCat SDK throws (`ErrorCode.networkError`, `.offlineConnectionError`, etc.). The plugin catches the error and dispatches `.refreshFailed(message)`.

#### `customerInfoStream() -> AsyncStream<EntitlementSnapshot>`

Long-lived stream. Wraps `Purchases.shared.customerInfoStream` and yields a new `EntitlementSnapshot` for every change RevenueCat reports — purchase, refund, family-share update, sandbox renewal.

The stream finishes when the underlying RevenueCat stream finishes. The plugin's `.observeCustomerInfo` effect normally keeps it alive for the duration of the session; cancel by cancelling the consuming `Task`, which terminates the stream and tears down the bridge.

The stream buffers only the newest snapshot: each yield is a complete entitlement state, so a slow consumer sees the latest value rather than replaying stale intermediate states.

#### `restorePurchases() async throws -> EntitlementSnapshot`

Maps the result of a restore. Reads `Purchases.shared.purchasesAreCompletedBy` live and branches: observer mode (`.myApp`) calls `syncPurchases()`, the default mode calls `restorePurchases()`. In observer mode the SDK's `restorePurchases()` can alias or transfer purchases between accounts, so the service uses `syncPurchases()` automatically — no special-casing in your app code. Throws whatever the SDK throws on error.

The plugin's `.restorePurchases` action wraps this call and dispatches `.customerInfoUpdated` on success or `.refreshFailed` on error.

## Entitlement mapping

For every `CustomerInfo` the service receives:

| Configuration | `isPro` | `hasPermanentLicense` |
|---|---|---|
| `entitlementID` active | `true` | (next column) |
| `entitlementID` inactive or missing | `false` | (next column) |
| `permanentLicenseEntitlementID == nil` | — | `false` |
| `permanentLicenseEntitlementID` active | — | `true` |
| `permanentLicenseEntitlementID` inactive or missing | — | `false` |

Both flags are checked independently against the same `CustomerInfo`. A user with both active subscription and lifetime entitlements gets both flags set. See <doc:EntitlementMapping> for the reasoning behind the truth table.

## See Also

- <doc:HowToImplementService>
- <doc:EntitlementMapping>
- <doc:MockServiceReference>
- ``RevenueCatPaywallService``
