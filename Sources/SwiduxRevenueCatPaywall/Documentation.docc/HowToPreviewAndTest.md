# How to Preview and Test

Drive entitlement state from SwiftUI previews and tests with `MockRevenueCatPaywallService` — no RevenueCat SDK call required.

## Overview

`MockRevenueCatPaywallService` is a `PaywallService` conformer that returns a configured snapshot from `customerInfo()` / `restorePurchases()` and exposes a streaming continuation through `send(_:)` and `finish()`. Plug it into the same `PaywallPlugin` you use in production. Drive entitlement transitions from your test or preview body.

For the API reference, see <doc:MockServiceReference>.

## Why a different mock from SwiduxPaywall's

`SwiduxPaywall` ships its own `MockPaywallService` whose stream finishes after the initial yield. That works for static "Pro" and "Free" previews but cannot model purchase, refund, or family-share transitions as a sequence. `MockRevenueCatPaywallService` keeps the stream open until you call `finish()`, which lets a single test verify the store reacts correctly to an *order* of snapshots.

When you only need a static state (one snapshot, one render pass), either mock works. When you need a sequence, use this one.

## Step 1: Make the service injectable

Plumb the service through your `Store.configured()` factory so previews and tests can override it:

```swift
extension Store where State == AppState, Action == AppAction {
    static func configured(
        paywallService: any PaywallService = RevenueCatPaywallService(entitlementID: "pro")
    ) -> AppStore {
        let plugins = PluginHost<AppState, AppAction>()
        plugins.register(
            PaywallPlugin<AppState, AppAction>(
                state: \.paywall,
                action: AppAction.paywall,
                extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
                service: paywallService
            )
        )
        return Store(initialState: AppState(), reducer: AppReducer().reduce, plugins: plugins)
    }
}
```

The default keeps the live RevenueCat path for app launch. Previews and tests pass an override.

## Step 2: Static previews — pick a state

Use the configured-state form when one snapshot is enough:

```swift
#Preview("Free") {
    let store = AppStore.configured(
        paywallService: MockRevenueCatPaywallService()
    )
    return ContentView().environment(store)
}

#Preview("Pro") {
    let store = AppStore.configured(
        paywallService: MockRevenueCatPaywallService(isPro: true)
    )
    return ContentView().environment(store)
}

#Preview("Lifetime") {
    let store = AppStore.configured(
        paywallService: MockRevenueCatPaywallService(hasPermanentLicense: true)
    )
    return ContentView().environment(store)
}
```

Each preview gets its own store; the mock's initial snapshot flows through `.observeCustomerInfo` and updates the gate before the first render.

## Step 3: Driving transitions in a test

When the test cares about a *sequence* of states — for example, the gate flipping from `false` to `true` after a purchase — use the streaming form:

```swift
@Test("Store updates when entitlement transitions to pro")
func storeReactsToProPurchase() async {
    let mock = MockRevenueCatPaywallService(isPro: false)
    let store = AppStore.configured(paywallService: mock)

    store.send(.paywall(.observeCustomerInfo))
    await Task.yield()
    #expect(store.paywall.isPro == false)

    mock.send(EntitlementSnapshot(isPro: true))
    await Task.yield()
    #expect(store.paywall.isPro)

    mock.finish()
}
```

Each `send(_:)` pushes a snapshot through the active stream subscriber, which in this case is the plugin's `observeCustomerInfo` effect. The store's reducer applies `.customerInfoUpdated`, the observer tree fires for changed properties, and the assertion sees the new value.

> Note: `customerInfoStream()` replaces its continuation on every call. If your test requests the stream more than once (rare — `observeCustomerInfo` is dispatched once), only the most recent subscriber receives `send(_:)` updates.

## Step 4: Driving transitions in a preview

Previews can drive transitions too — useful for verifying paywall sheet copy across states without running the app:

```swift
#Preview("Purchase flow") {
    let mock = MockRevenueCatPaywallService(isPro: false)
    let store = AppStore.configured(paywallService: mock)

    return ContentView()
        .environment(store)
        .task {
            store.send(.paywall(.observeCustomerInfo))
            try? await Task.sleep(for: .seconds(2))
            mock.send(EntitlementSnapshot(isPro: true))
        }
}
```

The preview starts in the free state, runs the gated UI for two seconds, then transitions to pro — letting you eyeball both copy paths in one preview pane.

## Step 5: Tear the stream down

Call `finish()` at the end of a test to terminate the stream cleanly:

```swift
mock.finish()
```

This causes any pending `for await … in stream` to exit. Without it, the consuming `Task` may stay alive until the test runner reaps it. Tests that own the mock for their full duration can skip this — Swift Testing tears down the task tree when the test exits — but it's a clean habit.

## See Also

- <doc:MockServiceReference>
- <doc:HowToImplementService>
- ``MockRevenueCatPaywallService``
