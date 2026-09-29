# How to Present the UI

Attach the `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers from `SwiduxRevenueCatPaywallUI` to a root view, driven by `PaywallState`.

## Overview

`SwiduxRevenueCatPaywallUI` ships three view modifiers that wrap RevenueCatUI's surfaces with platform-aware presentation. Each is bound to `PaywallState`: presentation flags drive visibility, and the bindings dispatch matching paywall actions back through the store on dismissal. There is no local sheet state.

For platform behavior details (adaptive iOS presentation, macOS sheet sizing, and the App Store deep link on macOS), see <doc:PlatformBehavior>.

## Before you start

This guide assumes:

- You have completed <doc:HowToImplementService>. The plugin is registered and `observeCustomerInfo` runs on launch.
- Your app target depends on the `SwiduxRevenueCatPaywallUI` product:

```swift
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
```

## Step 1: Attach one presentation host

The simplest wiring uses the `revenueCatPaywall(state:send:)` modifier for both presentation surfaces and their actions:

```swift
import SwiduxRevenueCatPaywallUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ContentView()
            .revenueCatPaywall(state: store.paywall) { action in
                store.send(.paywall(action))
            }
    }
}
```

The closure receives each `PaywallAction` emitted by the UI and lifts it into your root action. Attach the modifier once, to one app-wide presentation host. Do not attach it inside content created for every `WindowGroup` window or scene: the shared `PaywallState` request would make every copy present. In a multi-window app, choose one scene, such as the primary app or settings window, to own paywall presentation.

Both paywall modifiers accept `displayCloseButton:` (default `true`), `fonts:`, `presentationStyle:`, and `onEvent:`. See <doc:PlatformBehavior> before turning off the close button.

Use `onEvent` for analytics or app actions that distinguish purchase completion, cancellation, failure, restore completion, and restore failure. Its values contain only package-owned types and Foundation fields:

```swift
ContentView()
    .revenueCatPaywall(
        state: store.paywall,
        onEvent: { event in analytics.record(event) }
    ) { action in
        store.send(.paywall(action))
    }
```

### App-owned StoreKit 2 purchases

If RevenueCat is configured with `purchasesAreCompletedBy: .myApp` and `storeKitVersion: .storeKit2`, pass the app's StoreKit operations as `purchaseLogic`:

```swift
import StoreKit
import SwiduxRevenueCatPaywallUI

let purchaseLogic = RevenueCatPaywallPurchaseLogic(
    purchase: { product in
        try await product.purchase()
    },
    restore: {
        try await AppStore.sync()
    }
)

ContentView()
    .revenueCatPaywall(
        state: store.paywall,
        purchaseLogic: purchaseLogic
    ) { action in
        store.send(.paywall(action))
    }
```

RevenueCatUI requires both handlers in `.myApp` mode. The modifier always supplies them, so presenting without `purchaseLogic` returns a configuration error when the user tries to purchase or restore instead of triggering RevenueCatUI's Release-build trap. The purchase closure returns the original `Product.PurchaseResult`; the package reports it to RevenueCat and then finishes a verified transaction. A pending purchase stays open with a pending message. The restore closure refreshes StoreKit first, and the package then synchronizes RevenueCat and reports whether it found an active subscription or non-subscription.

The bundled observer-mode UI accepts StoreKit 2 products. A `.myApp` configuration pinned to StoreKit 1 can still use `RevenueCatPaywallService`, but it needs a custom paywall because `RevenueCatPaywallPurchaseLogic` does not expose `SKProduct` or `SKPaymentTransaction`.

## Step 2: Trigger the paywall from a feature

Dispatch `.request(reason:)` with a short identifier describing why you're asking. When `offeringIdentifier:` is omitted, the composed modifier passes this value to RevenueCat as a placement identifier. RevenueCat targeting can select an offering for that placement; otherwise the current offering is used:

```swift
Button("Export PDF") {
    store.send(.paywall(.request(reason: "export-pdf")))
}
```

The plugin sets `PaywallState.isPresented = true`. The `revenueCatPaywall` modifier observes the change and presents `RevenueCatUI.PaywallView` with the correct RevenueCat-owned or app-owned handlers.

An explicit `offeringIdentifier:` takes precedence over the placement. A missing explicit identifier asserts in Debug, logs a warning, and falls back to the current offering. Network failures fall back without asserting.

## Step 3: Trigger the customer center

Existing subscribers manage their subscription through the customer center. Surface a button that dispatches `.presentCustomerCenter`:

```swift
if store.paywall.isPro {
    Button("Manage Subscription") {
        store.send(.paywall(.presentCustomerCenter))
    }
}
```

The `revenueCatCustomerCenter` modifier presents `RevenueCatUI.CustomerCenterView` on iOS. On macOS, the convenience modifier dispatches `.openManageSubscriptions` so the paywall plugin opens the App Store subscriptions URL through its injectable URL handler, then dispatches `.dismissCustomerCenter`. RevenueCatUI does not ship a customer center on macOS; see <doc:PlatformBehavior>.

## Step 4: Manual wiring (optional)

If you need only one sheet, or you want to interleave other modifiers between them, attach the primitive modifiers directly. Each takes a real `Binding<Bool>`; build it with a `set:` that dispatches the matching dismiss action when SwiftUI clears the flag:

```swift
ContentView()
    .revenueCatPaywall(
        isPresented: Binding(
            get: { store.paywall.isPresented },
            set: { if !$0 { store.send(.paywall(.dismiss)) } }
        )
    )
    .revenueCatCustomerCenter(
        isPresented: Binding(
            get: { store.paywall.isCustomerCenterPresented },
            set: { if !$0 { store.send(.paywall(.dismissCustomerCenter)) } }
        )
    )
```

The convenience modifier `revenueCatPaywall(state:send:)` attaches this wiring and closes the paywall after a restore that leaves the user entitled. On iOS it also keeps the paywall and customer center mutually exclusive. The macOS customer center is an external App Store hand-off, so a request made while the paywall is open is handled immediately instead of being discarded.

## Step 5: Restore from inside the paywall

RevenueCatUI's `PaywallView` provides its own restore button by default. If you need an additional restore affordance elsewhere (a Settings row, for example), dispatch `.restorePurchases`:

```swift
Button("Restore Purchases") {
    store.send(.paywall(.restorePurchases))
}
.disabled(store.paywall.isLoading)
```

## What happens on dismiss

When the user dismisses the paywall, the plugin's `.dismiss` action clears `PaywallState.isPresented` and `requestedReason`, then dispatches `.refreshCustomerInfo` so the gate is reconciled — the user may have purchased while the sheet was open.

RevenueCatUI dismisses the paywall itself after a purchase, but not after a restore. The convenience modifier closes it for you: once RevenueCatUI reports the restore complete (after the user acknowledges its success alert) and `PaywallState.isGateSatisfied` is `true`, it dispatches `.dismiss`. The entitlement arrives through the live stream, so keep `.observeCustomerInfo` running. With the manual wiring, nothing closes the paywall after a restore — a user who restores behind a hard paywall (`displayCloseButton: false`) has no way out, so use the convenience modifier there.

When the user dismisses the customer center, the plugin's `.dismissCustomerCenter` action clears `isCustomerCenterPresented`. On macOS the convenience modifier sends that action immediately after `.openManageSubscriptions`. No refresh is dispatched, since opening the customer center does not change entitlement state by itself; the live `customerInfoStream` from `Step 5` of <doc:HowToImplementService> picks up any subscription change RevenueCat reports asynchronously.

## Dashboard exit offers

Dashboard exit offers do not run through the bundled modifiers. RevenueCatUI implements them only in its own presentation modifiers, and those presenters always add a close button. The bundled modifiers keep supporting `displayCloseButton: false` as a hard paywall, so they continue to embed `PaywallView` directly. Use RevenueCatUI's `presentPaywall` modifier when an exit offer matters more than the hard-paywall option.

## See Also

- <doc:PlatformBehavior>
- <doc:HowToImplementService>

The matching API reference for the views described here lives in the `SwiduxRevenueCatPaywallUI` documentation.
