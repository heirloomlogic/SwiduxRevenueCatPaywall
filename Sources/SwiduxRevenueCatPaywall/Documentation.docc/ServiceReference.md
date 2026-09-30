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
    @MainActor public func logIn(appUserID: String) async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult
    @MainActor public func logOut() async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult
}
```

Value type. Holds two `String` identifiers and forwards configured calls to `Purchases.shared`. It is safe to construct before `RevenueCatPaywall.configure` runs. For production, wrap it in SwiduxPaywall's `ResilientPaywallService` so a transient read failure at launch never gates a paid user as free.

#### Initializer

```swift
public init(
    entitlementID: String,
    permanentLicenseEntitlementID: String? = nil
)
```

- `entitlementID` — RevenueCat entitlement identifier that grants pro access. Surfaces as `EntitlementSnapshot.isPro` when active.
- `permanentLicenseEntitlementID` — Optional secondary identifier for a lifetime / permanent entitlement. Surfaces as `EntitlementSnapshot.hasPermanentLicense` when active. Pass `nil` if the app has no separate lifetime SKU.

> Important: Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` before invoking the service. Construction before configuration is safe, including from a stored-property initializer. Previews and tests that do not configure RevenueCat should still use `MockRevenueCatPaywallService` when they need entitlement values.

#### `customerInfo() async throws -> EntitlementSnapshot`

One-shot fetch. Calls `Purchases.shared.customerInfo()` and maps the result. A response older than five minutes by `requestDate` is labelled `.cache` (see <doc:EntitlementMapping#Live-and-cached-customer-info>).

A read that starts during a package login or logout waits for it to finish. If an identity operation begins, or the RevenueCat app user ID changes, before the read returns, the result is discarded.

Throws ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/identityChanged`` when the result was discarded, ``RevenueCatPaywallError/verificationFailed`` for failed signature verification, or an SDK error. A `ResilientPaywallService` retries a failed read and can then serve its cached entitlement; that cache is not tied to an account (see <doc:HowToImplementService#Account-changes>). Without a fallback the plugin dispatches `.refreshFailed(message)`.

#### `customerInfoStream() -> AsyncStream<EntitlementSnapshot>`

Long-lived stream. Wraps `Purchases.shared.customerInfoStream` and yields a new `EntitlementSnapshot` for each valid change RevenueCat reports. A failed-verification element is skipped.

The stream finishes when the underlying RevenueCat stream finishes. The plugin's `.observeCustomerInfo` effect normally keeps it alive for the duration of the session; cancel by cancelling the consuming `Task`, which terminates the stream and tears down the bridge.

Before configuration, the stream logs a fault and finishes immediately. Swidux 1.9 and later clears its observation guard when the stream ends, so configure RevenueCat and dispatch `.observeCustomerInfo` again to retry.

The stream stays open across package logins and logouts without forwarding a value that could belong to the previous identity. Each RevenueCat subscription starts while no identity operation is running. The first value that arrives after an identity operation began, or after the app user ID changed, is dropped together with the subscription and anything it still buffered. A new subscription starts once no identity operation is running. RevenueCat begins every subscription by replaying the customer info it last sent, and an identity change does not replace that value: after a logout that failed offline it is still the previous user's. The stream forwards that first value only when its `originalAppUserId` matches the current app user ID or the `originalAppUserId` of the customer info RevenueCat caches for that ID.

The stream buffers only the newest snapshot: each yield is a complete entitlement state, so a slow consumer sees the latest value rather than replaying stale intermediate states.

A new stream first yields the customer info RevenueCat last delivered in this process, if any, and only when it belongs to the current RevenueCat customer. RevenueCat may not have delivered one yet — on a relaunch with a fresh cache it skips the launch fetch — or may still hold the previous user's. The stream then stays silent until the next change, so dispatch `.refreshCustomerInfo` alongside `.observeCustomerInfo` to seed the state.

#### `restorePurchases() async throws -> EntitlementSnapshot`

Maps the result of RevenueCat's user-initiated `restorePurchases()` flow in every purchase-completion mode. Unlike `syncPurchases()`, this flow refreshes the App Store receipt and can recover a subscription missing from the device receipt. It may show an App Store sign-in prompt and applies the RevenueCat project's restore behavior when purchases belong to another app user ID. It follows the same identity rule as `customerInfo()`. It throws ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/identityChanged`` when the identity changed before the restore returned, ``RevenueCatPaywallError/verificationFailed`` for failed signature verification, or an SDK error.

The plugin's `.restorePurchases` action wraps this call and dispatches `.customerInfoUpdated` on success or `.refreshFailed` on error.

#### Identity operations

`logIn(appUserID:)` and `logOut()` switch the RevenueCat identity and map the returned customer info with the same entitlement identifiers and verification policy as `customerInfo()`. Their ``RevenueCatPaywallIdentityResult`` reports the identity observed after the call, whether it differs from the identity observed before the call, and the mapped snapshot. An already-anonymous logout skips the SDK logout operation and may return `nil` for its snapshot when no cached customer info passes the verification policy.

Failed signature verification is rejected. With `entitlementVerification: .disabled`, `.notRequested` responses are accepted without a signature check.

All package login/logout calls are serialized through completion, including the deprecated namespace methods. Direct RevenueCat identity calls bypass that serialization. A returned result records the completed operation; later queued operations may change the identity again.

Both methods throw ``RevenueCatPaywallIdentityError`` instead of exposing RevenueCat errors. The error records the operation, a package-owned reason, and the identity observed before and after the failure. A provider operation can change identity before a later request or verification step fails, so callers must inspect `identityChanged` rather than treating every thrown error as an unchanged identity.

Every package identity operation, including one that fails, makes the service discard overlapping reads, restores, and stream values as described above. The operation does not reset `PaywallState` or remove the `ResilientPaywallService` cache, and it cannot recall a stream value delivered before it began. <doc:HowToImplementService#Account-changes> lists what the app does after each operation. The customer-info stream may later repeat a successful operation's result, but a failed offline transition is not guaranteed to yield a stream value.

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
- ``RevenueCatPaywallError``
- ``RevenueCatPaywallIdentity``
- ``RevenueCatPaywallIdentityResult``
- ``RevenueCatPaywallIdentityError``
