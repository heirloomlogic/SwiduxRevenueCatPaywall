# How to Preview and Test

Drive entitlement state from SwiftUI previews and tests with `MockRevenueCatPaywallService` — no RevenueCat SDK call required.

## Overview

`MockRevenueCatPaywallService` is a `PaywallService` conformer that tracks a *current* snapshot, the way the real service reflects RevenueCat's state: `send(_:)` updates it and delivers it to every open stream, `customerInfo()` / `restorePurchases()` return it, and `finish()` ends the open streams. Plug it into the same `PaywallPlugin` you use in production. Drive entitlement transitions from your test or preview body.

For the API reference, see <doc:MockServiceReference>.

## Why a different mock from SwiduxPaywall's

`SwiduxPaywall` ships its own `MockPaywallService` whose stream finishes after the initial yield. That works for static "Pro" and "Free" previews but cannot model purchase, refund, or family-share transitions as a sequence. `MockRevenueCatPaywallService` keeps the stream open until you call `finish()`, which lets a single test verify the store reacts correctly to an *order* of snapshots.

When you only need a static state (one snapshot, one render pass), either mock works. When you need a sequence, use this one.

The mock is built for deterministic tests, so it differs from the real `RevenueCatPaywallService` in two ways: a stream buffers every value its consumer has not read yet (the real stream keeps only the newest), and a new stream always yields the current snapshot first (the real stream does so only if RevenueCat has already delivered customer info in this process). Don't rely on either behavior to prove production code correct.

Swidux's `SimulatedPaywallService` (in `SwiduxPaywall`) is the other option. It is an actor driven from the dev paywall UI in `SwiduxDevPaywallUI`, can simulate latency, and needs no RevenueCat dependency, which makes it the better fit for vendor-free previews and development builds. Prefer `MockRevenueCatPaywallService` in tests that need a synchronous `send(_:)`, arbitrary injected errors, `finish()`, or delivery of repeated identical snapshots — `SimulatedPaywallService` drops a change equal to the current state.

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

Each preview gets its own store. The store starts from `PaywallState`'s free default; when the root view's `.task` dispatches `.observeCustomerInfo` and `.refreshCustomerInfo` (as in <doc:GettingStarted>), the mock answers with its initial snapshot and the gate updates. Effects run asynchronously, so that happens just after the first render, not before it — the first frame of the "Pro" and "Lifetime" previews briefly shows the free state.

## Step 3: Driving transitions in a test

When the test cares about a *sequence* of states — for example, the gate flipping to `true` after a purchase and back to `false` after a refund — use the streaming form.

Swidux runs effects as unstructured tasks, so a state change driven by an effect lands at some later point: after `store.send(_:)` or `mock.send(_:)` returns, no fixed number of `await Task.yield()` calls guarantees the store has caught up. Poll for the state you expect with a bounded wait instead. Add a helper like this one to your test target:

```swift
import Testing

/// Polls `condition` on the main actor until it holds; records a failure and throws once
/// `timeout` elapses without it holding.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            try #require(condition(), "Timed out after \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
```

Store tests run on the main actor, because `Store` and its `send(_:)` are `@MainActor`:

```swift
@Test("Store follows entitlement transitions: purchase, then refund")
@MainActor
func storeFollowsEntitlementTransitions() async throws {
    let mock = MockRevenueCatPaywallService(isPro: false)
    let store = AppStore.configured(paywallService: mock)
    store.send(.paywall(.observeCustomerInfo))

    mock.send(EntitlementSnapshot(isPro: true))
    try await waitUntil { store.paywall.isPro }

    mock.send(EntitlementSnapshot(isPro: false))
    try await waitUntil { !store.paywall.isPro }

    mock.finish()
}
```

Each `send(_:)` makes the snapshot current and delivers it to every open stream — here, the one the plugin's `observeCustomerInfo` effect consumes. The effect dispatches `.customerInfoUpdated`, the plugin updates `store.paywall`, and the wait sees the new value. The stream delivers values in order and buffers them until the effect reads them, so a `send(_:)` that runs before the effect has subscribed is not lost: the new stream yields the current snapshot first. Because `customerInfo()` also returns the sent snapshot, the refresh the plugin dispatches when the paywall is dismissed sees the purchased state too — the gate never regresses to the init-time value mid-test.

Streams fan out, so one mock can feed several consumers at once — two stores, or a `ResilientPaywallService` wrapper alongside your own reader — and each receives every `send(_:)`.

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

## Step 5: Simulating failures

Set `customerInfoError` or `restoreError` to make the corresponding call throw — the plugin dispatches `.refreshFailed`, sets `store.paywall.error`, and your retry UI becomes testable:

```swift
@Test("Refresh failure surfaces an error the UI can retry from")
@MainActor
func refreshFailureSurfacesError() async throws {
    struct Offline: Error {}
    let mock = MockRevenueCatPaywallService(isPro: false)
    let store = AppStore.configured(paywallService: mock)

    mock.customerInfoError = Offline()
    store.send(.paywall(.refreshCustomerInfo))
    try await waitUntil { store.paywall.error != nil }

    mock.customerInfoError = nil
    store.send(.paywall(.refreshCustomerInfo))
    try await waitUntil { store.paywall.error == nil }
}
```

The same hooks exercise `ResilientPaywallService`'s last-known-good fallback: wrap the mock, make `customerInfo()` throw, and assert the cached entitlement holds.

## Step 6: Tear the streams down

Call `finish()` at the end of a test to end every stream the mock has open:

```swift
mock.finish()
```

Each open stream delivers what it has buffered, then its `for await` loop exits, so the plugin's `observeCustomerInfo` effect task completes. Don't skip this in store-driven tests: Swidux runs effects as unstructured tasks, which Swift Testing does not cancel when the test returns, so without `finish()` the effect task stays suspended on the stream, holding the mock, for the rest of the test process. The mock stays usable afterwards — `send(_:)` keeps updating the current snapshot, and a stream requested later is live again.

## See Also

- <doc:MockServiceReference>
- <doc:HowToImplementService>
- ``MockRevenueCatPaywallService``
