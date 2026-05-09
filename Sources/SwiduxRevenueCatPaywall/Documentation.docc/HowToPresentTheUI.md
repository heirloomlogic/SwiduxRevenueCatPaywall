# How to Present the UI

Attach `PaywallSheet` and `CustomerCenterSheet` from `SwiduxRevenueCatPaywallUI` to a root view, driven by `PaywallState`.

## Overview

`SwiduxRevenueCatPaywallUI` ships two SwiftUI views and a convenience modifier that wrap RevenueCatUI's surfaces with platform-aware presentation. Each is bound to `PaywallState`: presentation flags drive visibility, dismissal closures dispatch matching paywall actions back through the store. There is no local sheet state.

For platform behavior details (iOS `fullScreenCover` vs macOS sheet sizing, App Store deep link on macOS), see <doc:PlatformBehavior>.

## Before you start

This guide assumes:

- You have completed <doc:HowToImplementService>. The plugin is registered and `observeCustomerInfo` runs on launch.
- Your app target depends on the `SwiduxRevenueCatPaywallUI` product:

```swift
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
```

## Step 1: Attach both sheets to a root view

The simplest wiring uses the `revenueCatPaywall(state:send:)` modifier — one call, both sheets, both dismissals:

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

The closure receives a `PaywallAction` (`.dismiss` or `.dismissCustomerCenter`) and lifts it into your root action. Place the modifier on the topmost view that should host both sheets.

## Step 2: Trigger the paywall from a feature

Dispatch `.request(reason:)` with a short identifier describing why you're asking. `PaywallState.requestedReason` stores the value so the sheet (or analytics) can tailor its copy:

```swift
Button("Export PDF") {
    store.send(.paywall(.request(reason: "export-pdf")))
}
```

The plugin sets `PaywallState.isPresented = true`. `PaywallSheet` observes the change and presents `RevenueCatUI.PaywallView`.

## Step 3: Trigger the customer center

Existing subscribers manage their subscription through the customer center. Surface a button that dispatches `.presentCustomerCenter`:

```swift
if store.paywall.isPro {
    Button("Manage Subscription") {
        store.send(.paywall(.presentCustomerCenter))
    }
}
```

`CustomerCenterSheet` presents `RevenueCatUI.CustomerCenterView` on iOS. On macOS it opens the system App Store subscriptions URL and immediately fires `onDismiss` (RevenueCatUI does not ship a customer center on macOS — see <doc:PlatformBehavior>).

## Step 4: Manual wiring (optional)

If you need only one sheet, or you want to interleave other modifiers between them, attach each manually:

```swift
ContentView()
    .background(
        PaywallSheet(
            isPresented: store.paywall.isPresented,
            onDismiss: { store.send(.paywall(.dismiss)) }
        )
    )
    .background(
        CustomerCenterSheet(
            isPresented: store.paywall.isCustomerCenterPresented,
            onDismiss: { store.send(.paywall(.dismissCustomerCenter)) }
        )
    )
```

The modifier form is exactly equivalent to this wiring.

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

When the user dismisses the customer center, the plugin's `.dismissCustomerCenter` action clears `isCustomerCenterPresented`. No refresh is dispatched, since opening the customer center does not change entitlement state by itself; the live `customerInfoStream` from `Step 5` of <doc:HowToImplementService> picks up any subscription change RevenueCat reports asynchronously.

## See Also

- <doc:PlatformBehavior>
- <doc:HowToImplementService>

The matching API reference for the views described here lives in the `SwiduxRevenueCatPaywallUI` documentation.
