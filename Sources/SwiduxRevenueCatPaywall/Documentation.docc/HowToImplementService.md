# How to Implement the Service

Wire `RevenueCatPaywallService` into the `SwiduxPaywall` plugin so the store sees real-time entitlement updates from RevenueCat.

## Overview

This guide takes you from a wired Swidux app with a paywall slice to a live RevenueCat-backed entitlement pipeline. It covers SDK configuration, plugin registration, observation lifecycle, and refresh/restore flows.

For the API-level reference of the service, see <doc:ServiceReference>. For the entitlement mapping rules, see <doc:EntitlementMapping>. For the upstream plugin contract — actions, state shape, dispatch semantics — see Swidux's *Add a Paywall* and *SwiduxPaywall Reference*; this guide does not repeat that material.

## Before you start

This guide assumes:

- You have a wired Swidux app — `AppState`, `AppAction`, `AppReducer`, `AppStore` exist, and the store is in the SwiftUI environment.
- Your `AppState` already has a `paywall: PaywallState` slice and your `AppAction` has a `.paywall(PaywallAction)` case. If not, follow Swidux's *Add a Paywall* guide first.
- You have a RevenueCat project, an API key, and at least one entitlement identifier configured in the RevenueCat dashboard.

## Step 1: Add the dependencies

Add both Swift packages to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.10.0"),
    .package(url: "https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall", from: "1.0.0"),
],
```

Add the products you need to your app target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Swidux", package: "Swidux"),
        .product(name: "SwiduxPaywall", package: "Swidux"),
        .product(name: "SwiduxRevenueCatPaywall", package: "SwiduxRevenueCatPaywall"),
        .product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
    ]
)
```

`SwiduxRevenueCatPaywallUI` is optional — drop it if you don't need the bundled sheets.

## Step 2: Configure the paywall at launch

`RevenueCatPaywallService` calls into `Purchases.shared` under the hood. Configure the paywall before constructing the store:

```swift
// MyApp.swift
import SwiduxRevenueCatPaywall
import SwiftUI

@main
struct MyApp: App {
    @State private var store: AppStore

    init() {
        RevenueCatPaywall.configure(apiKey: "your_revenuecat_api_key")
        _store = State(wrappedValue: AppStore.configured())
    }

    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}
```

If users sign in after launch, switch the purchase identity through the base `RevenueCatPaywallService` you construct in Step 3. Successful calls return the identity observed when the operation completes and the mapped entitlement snapshot from the operation:

```swift
let login = try await revenueCatService.logIn(appUserID: account.id)
let logout = try await revenueCatService.logOut()
```

The same verification policy applies to reads and identity results: failed verification is rejected, while `entitlementVerification: .disabled` accepts `.notRequested` responses without a signature check. A returned snapshot does not itself prove signature verification ran.

`logOut()` remains a no-op when RevenueCat is already anonymous. Its result contains a cached snapshot accepted by the verification policy when one is available; otherwise `snapshot` is `nil`. The older `RevenueCatPaywall.logIn(appUserID:)` and `RevenueCatPaywall.logOut()` entry points remain for source compatibility and now map failures to ``RevenueCatPaywallIdentityError``, but they are deprecated because they do not return the mapped snapshot.

Catch ``RevenueCatPaywallIdentityError`` and inspect `identityChanged`, `identityBefore`, and `identityAfter`. RevenueCat can change its local identity before a later network or verification step fails, so a thrown error does not mean the old identity is still active. The error's `reason` maps provider errors into package-owned cases such as `networkUnavailable` and `invalidAppUserID`; application targets do not need to import RevenueCat.

The entitlement stream is an observation channel, not confirmation that an identity operation finished. It can repeat the operation's customer info later, and an offline operation that throws after changing identity may produce no stream value. Use the operation result or error as the immediate transition record, then refresh after connectivity returns.

The service identity methods are main-actor isolated. SwiftUI tasks can call them directly; background callers must hop to `MainActor`. All package login/logout entry points share a queue, including calls on different service instances and the deprecated namespace methods. Each operation holds its turn through result mapping and error sampling. Calls made directly through RevenueCat bypass this queue, so use the package methods for identity changes. Results record an operation’s completion; a later queued operation can change the identity again.

### Account changes

At every package login and logout, including one that throws after RevenueCat already changed identity, the service discards its own results that could belong to the previous identity:

- A `customerInfo()` or `restorePurchases()` call that starts while a login or logout is running waits for it to finish.
- A read or restore that returns after an identity operation began, or after the RevenueCat app user ID changed, throws ``RevenueCatPaywallError/identityChanged`` instead of returning the previous identity's entitlements. `ResilientPaywallService` treats that like any failed read: it retries, and the retry reads the new identity.
- The entitlement stream stays open, but it drops a RevenueCat subscription as soon as a value arrives after an identity change, along with anything that subscription still buffered. It subscribes again once no identity operation is running. RevenueCat starts that subscription by replaying the customer info it last sent, which can still be the previous user's after an offline logout, so the stream forwards the replay only when it belongs to the current RevenueCat customer.

Three things remain the app's job, because the adapter does not own the plugin state or the decorator's cache:

- **Displayed state.** `PaywallState` keeps the previous account's entitlements until something replaces them. Dispatch the operation's snapshot, or a free snapshot when there is none, as soon as the operation returns or throws with `identityChanged`. The plugin then ignores any refresh or restore that started before it.
- **The decorator cache.** `ResilientPaywallService` keeps one last-known-good entry that is not tied to an account. A failed read after the switch can fall back to the previous account's entry until you remove it. Remove it before the operation, so a crash mid-switch cannot carry it into the next launch, and again afterwards, in case a read finished and saved it before the operation began. `removeValue(for:)` returns `false` when the Keychain refuses the deletion, for example while the device is locked; the entry is still there, so don't refresh until a removal succeeds.
- **Values already delivered.** A stream value the service delivered before the operation began can still be waiting in a buffer further down, such as the decorator's stream. The service cannot recall it, and the plugin applies it when it arrives.

```swift
@MainActor
func changePurchaseAccount(
    _ operation: () async throws -> RevenueCatPaywallIdentityResult
) async {
    cacheStore.removeValue(for: .lastKnownEntitlement)
    let snapshot: EntitlementSnapshot?
    do {
        snapshot = try await operation().snapshot
    } catch let error as RevenueCatPaywallIdentityError where error.identityChanged {
        snapshot = nil
    } catch {
        return  // The identity did not change.
    }
    store.send(.paywall(.customerInfoUpdated(snapshot ?? EntitlementSnapshot())))
    guard cacheStore.removeValue(for: .lastKnownEntitlement) else { return }  // Retry before refreshing.
    store.send(.paywall(.refreshCustomerInfo))
}

await changePurchaseAccount { try await revenueCatService.logIn(appUserID: account.id) }
await changePurchaseAccount { try await revenueCatService.logOut() }
```

`cacheStore` is the `KeychainKeyValueStore` you pass to `ResilientPaywallService` in Step 3. Swidux's `ResilientPaywallService.clearCache()` will replace the direct removal once a Swidux release includes it; [issue #46](https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/issues/46) tracks that. Purchase identity is separate from any iCloud or app account: change it only when the purchase account changes.

> Important: Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` before dispatching paywall work. Constructing `RevenueCatPaywallService` earlier is safe, but reads and restores throw ``RevenueCatPaywallError/notConfigured`` and the entitlement stream finishes immediately until configuration runs.

### App-owned StoreKit 2 purchases

When the app owns purchases, configure with `purchasesAreCompletedBy: .myApp` and the StoreKit version the app uses. For StoreKit 2 purchases made outside the bundled paywall, report the original result before finishing a verified transaction:

```swift
import StoreKit
import SwiduxRevenueCatPaywall

let result = try await product.purchase()
try await RevenueCatPaywall.recordPurchase(result)

if case .success(.verified(let transaction)) = result {
    await transaction.finish()
}
```

The package exposes only StoreKit types. Apps do not import RevenueCat. The bundled paywall performs this reporting and finishing sequence when you pass `RevenueCatPaywallPurchaseLogic`; see <doc:HowToPresentTheUI>.

## Step 3: Construct the service

Create the service with the entitlement identifier you set up in the RevenueCat dashboard:

```swift
import SwiduxPaywall
import SwiduxRevenueCatPaywall

let revenueCatService = RevenueCatPaywallService(entitlementID: "pro")
let service = ResilientPaywallService(
    base: revenueCatService,
    store: KeychainKeyValueStore(service: "com.example.myapp")
)
```

Back this cache with the Keychain as shown; a `UserDefaults` plist is user-editable and can be restored from a doctored backup. The cache is not tied to an account, so remove it when the purchase account changes (see <doc:HowToImplementService#Account-changes>).

`ResilientPaywallService` (from SwiduxPaywall) persists the last entitlement snapshot a successful read delivered, so a slow or failing network at cold launch never gates a paying user as free — the last-known-good state holds until live data arrives, and a genuine lapse is honoured on the next successful read. The bare `RevenueCatPaywallService` works too, but for production the resilient wrapper is the right default.

If your app sells a separate lifetime SKU alongside a subscription, see <doc:HowToAddAPermanentLicense> for the dual-entitlement form.

## Step 4: Register the paywall plugin

Pass the service to `PaywallPlugin` when wiring the store:

```swift
// AppStore.swift
import Swidux
import SwiduxPaywall
import SwiduxRevenueCatPaywall

extension Store where State == AppState, Action == AppAction {
    static func configured() -> AppStore {
        let plugins = PluginHost<AppState, AppAction>()

        plugins.register(
            PaywallPlugin<AppState, AppAction>(
                state: \.paywall,
                action: AppAction.paywall,
                extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
                service: ResilientPaywallService(
                    base: RevenueCatPaywallService(entitlementID: "pro"),
                    store: KeychainKeyValueStore(service: "com.example.myapp")
                )
            )
        )

        return Store(
            initialState: AppState(),
            reducer: AppReducer().reduce,
            plugins: plugins
        )
    }
}
```

The plugin owns reducing for `.paywall` actions; your root reducer should fall through with `return nil` for that case.

## Step 5: Observe customer info on launch

Start the entitlement stream once, on the root view:

```swift
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        RootContent()
            .task {
                store.send(.paywall(.observeCustomerInfo))
                store.send(.paywall(.refreshCustomerInfo))
            }
    }
}
```

`observeCustomerInfo` returns a long-lived effect that consumes `RevenueCatPaywallService.customerInfoStream()`. Every snapshot the service yields flows through `.customerInfoUpdated` and updates `store.paywall.isPro` / `hasPermanentLicense`. The effect lives for the duration of the stream, so the store stays in sync with RevenueCat without polling.

The accompanying `refreshCustomerInfo` seeds the state. A new stream yields the customer info RevenueCat last delivered in this process when that info belongs to the current RevenueCat customer, but RevenueCat may not have delivered one yet — on a relaunch with a fresh cache it skips the launch fetch — and the stream then stays silent until the next change.

If observation starts before configuration, the stream finishes. Swidux 1.9 and later clears its observation guard at that point. After configuring RevenueCat, dispatch both `.observeCustomerInfo` and `.refreshCustomerInfo` again; the new stream uses `Purchases.shared` and the refresh seeds current state.

## Step 6: Gate features

Read `store.paywall.isGateSatisfied` before running gated work. If it's `false`, dispatch `.request(reason:)` instead:

```swift
Button("Export PDF") {
    if store.paywall.isGateSatisfied {
        store.send(.export(.exportPDF))
    } else {
        store.send(.paywall(.request(reason: "export-pdf")))
    }
}
```

`isGateSatisfied` returns `true` when the user holds an active pro subscription **or** a permanent license — feature code does not need to know which.

## Step 7: Wire the UI

To present `RevenueCatUI.PaywallView` and the customer center, attach the bundled modifier once to one app-wide presentation host. See <doc:HowToPresentTheUI>.

## Step 8: Restore purchases

Add a restore button to your paywall UI. Reflect `store.paywall.isLoading` to disable it while the call is in flight:

```swift
Button("Restore Purchases") {
    store.send(.paywall(.restorePurchases))
}
.disabled(store.paywall.isLoading)
```

The plugin calls `RevenueCatPaywallService.restorePurchases()`, which forwards to RevenueCat's user-initiated `restorePurchases()` flow in both completion modes. That flow refreshes the App Store receipt before posting transactions, so it can recover subscriptions missing from the device receipt. On success the resulting snapshot flows through `.customerInfoUpdated` and updates the gate. On failure, `store.paywall.error` is set.

`syncPurchases()` remains useful for background migration after login, but it reads only the receipt already on the device and can alias or transfer purchases under the RevenueCat project's restore behavior. It is not the implementation of the explicit Restore Purchases action.

## Step 9: Handle errors

Before RevenueCat is configured, reads and restores throw ``RevenueCatPaywallError/notConfigured``. Identity operations throw ``RevenueCatPaywallIdentityError`` with `reason == .notConfigured`. A failed signature throws ``RevenueCatPaywallError/verificationFailed`` during an entitlement read and maps to `RevenueCatPaywallIdentityError.Reason.verificationFailed` during an identity operation. A read or restore whose identity changed before it returned throws ``RevenueCatPaywallError/identityChanged``. Other identity failures are also mapped to package-owned reasons; ordinary reads and restores can still propagate SDK errors. The plugin handles failed reads with `.refreshFailed(message)` when no valid cache fallback exists. Read `store.paywall.error` from your paywall view to surface a retry affordance:

```swift
if let error = store.paywall.error {
    Text(error)
        .foregroundStyle(.red)
    Button("Retry") {
        store.send(.paywall(.refreshCustomerInfo))
    }
}
```

## See Also

- <doc:ServiceReference>
- <doc:HowToAddAPermanentLicense>
- <doc:HowToPresentTheUI>
- <doc:EntitlementMapping>
