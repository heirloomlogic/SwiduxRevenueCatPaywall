# Getting Started with SwiduxRevenueCatPaywall

Add the package, configure RevenueCat, register the paywall plugin, and present the bundled sheets.

## Overview

This guide walks through the four steps to integrate `SwiduxRevenueCatPaywall` into a Swidux app: add the package, configure RevenueCat, register the plugin, and attach the UI. It is the shortest path from a wired Swidux app to a working paywall. For deeper coverage of any step, follow the linked how-tos.

This package assumes you already use Swidux. If you don't, work through Swidux's own getting-started guide first.

## Add the Package

**Xcode:** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall`. Add the products you need:

- `SwiduxRevenueCatPaywall` — the `PaywallService` implementation and mock.
- `SwiduxRevenueCatPaywallUI` — adds the `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers (depends on RevenueCatUI).

**Package.swift:**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall", branch: "main"),
```

```swift
.product(name: "SwiduxRevenueCatPaywall", package: "SwiduxRevenueCatPaywall"),
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
```

## Configure RevenueCat at launch

`RevenueCatPaywallService` calls into `Purchases.shared`. Configure the SDK before constructing the store:

```swift
// MyApp.swift
import RevenueCat
import SwiftUI

@main
struct MyApp: App {
    @State private var store: AppStore

    init() {
        Purchases.configure(withAPIKey: "your_revenuecat_api_key")
        _store = State(wrappedValue: AppStore.configured())
    }

    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}
```

## Register the paywall plugin

Pass `RevenueCatPaywallService` to `PaywallPlugin` in your `Store.configured()` factory:

```swift
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
                service: RevenueCatPaywallService(entitlementID: "pro")
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

Start the entitlement stream on the root view so the gate reflects RevenueCat's state from launch:

```swift
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        RootContent()
            .task { store.send(.paywall(.observeCustomerInfo)) }
    }
}
```

Gate features by reading `store.paywall.isGateSatisfied`. See <doc:HowToImplementService> for the full plugin lifecycle.

## Attach the UI

Attach the `revenueCatPaywall` modifier to a root view, driven by paywall state:

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

Trigger the paywall from a gated feature with `.paywall(.request(reason:))`:

```swift
Button("Export PDF") {
    if store.paywall.isGateSatisfied {
        store.send(.export(.exportPDF))
    } else {
        store.send(.paywall(.request(reason: "export-pdf")))
    }
}
```

See <doc:HowToPresentTheUI> for manual wiring with the primitive modifiers, customer-center triggering, and dismiss semantics.

## Next Steps

- <doc:HowToImplementService> — Detailed walkthrough of the service lifecycle and error handling.
- <doc:HowToAddAPermanentLicense> — Add a lifetime entitlement alongside the subscription.
- <doc:HowToPreviewAndTest> — Drive entitlement state from previews and tests.
- <doc:HowToPresentTheUI> — Wire the bundled view modifiers.
- <doc:PlatformBehavior> — Why iOS and macOS behave differently.
- <doc:EntitlementMapping> — How RevenueCat entitlements map to `EntitlementSnapshot`.
