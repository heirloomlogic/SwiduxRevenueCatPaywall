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
    .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.3.0"),
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

If users sign in after launch, switch the purchase provider to them with `RevenueCatPaywall.logIn(appUserID:)` and back with `RevenueCatPaywall.logOut()` — like `configure`, these wrappers keep the RevenueCat import out of your app target. The entitlement stream delivers the new user's entitlements automatically.

> Important: `Purchases.shared` traps if used unconfigured. Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` before anything that constructs `RevenueCatPaywallService`, including SwiftUI previews — guard preview-only code with `MockRevenueCatPaywallService` instead.

## Step 3: Construct the service

Create the service with the entitlement identifier you set up in the RevenueCat dashboard:

```swift
import SwiduxPaywall
import SwiduxRevenueCatPaywall

let service = ResilientPaywallService(
    base: RevenueCatPaywallService(entitlementID: "pro"),
    store: UserDefaultsKeyValueStore()
)
```

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
                    store: UserDefaultsKeyValueStore()
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
            .task { store.send(.paywall(.observeCustomerInfo)) }
    }
}
```

`observeCustomerInfo` returns a long-lived effect that consumes `RevenueCatPaywallService.customerInfoStream()`. Every snapshot the service yields flows through `.customerInfoUpdated` and updates `store.paywall.isPro` / `hasPermanentLicense`. The effect lives for the duration of the stream, so the store stays in sync with RevenueCat without polling.

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

To present `RevenueCatUI.PaywallView` and the customer center, attach the bundled sheets to a root view. See <doc:HowToPresentTheUI>.

## Step 8: Restore purchases

Add a restore button to your paywall UI. Reflect `store.paywall.isLoading` to disable it while the call is in flight:

```swift
Button("Restore Purchases") {
    store.send(.paywall(.restorePurchases))
}
.disabled(store.paywall.isLoading)
```

The plugin calls `RevenueCatPaywallService.restorePurchases()`, which forwards to `Purchases.shared.restorePurchases()`. On success the resulting snapshot flows through `.customerInfoUpdated` and updates the gate. On failure, `store.paywall.error` is set.

> Warning: If you configured `purchasesAreCompletedBy: .myApp`, restore behaves differently: in that mode RevenueCat recommends `syncPurchases()` over `restorePurchases()`, because a restore can alias or transfer purchases between accounts. Handle restore in your own StoreKit code rather than dispatching `.restorePurchases`.

## Step 9: Handle errors

The service throws whatever `Purchases.shared` throws — `ErrorCode.networkError`, `.offlineConnectionError`, configuration errors, etc. The plugin catches the error and dispatches `.refreshFailed(message)`. Read `store.paywall.error` from your paywall view to surface a retry affordance:

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
