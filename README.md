# SwiduxRevenueCatPaywall

**RevenueCat adapter for Swidux's `PaywallPlugin`.** Implements `PaywallService` against `Purchases.shared`, ships a controllable mock for previews and tests, and provides drop-in SwiftUI sheets that wrap RevenueCatUI's `PaywallView` and `CustomerCenterView` with platform-aware presentation.

## Why this package

- **Drop-in `PaywallService` conformance.** `RevenueCatPaywallService` maps `CustomerInfo` to Swidux's `EntitlementSnapshot` and forwards `customerInfoStream` so the plugin sees real-time entitlement changes.
- **Optional permanent-license entitlement.** A second entitlement ID can be checked alongside the standard pro entitlement and surfaces as `EntitlementSnapshot.hasPermanentLicense`.
- **Preview- and test-friendly mock.** `MockRevenueCatPaywallService` exposes `send(_:)` and `finish()` so tests and previews can drive entitlement transitions over time — unlike `MockPaywallService` from SwiduxPaywall, which finishes its stream immediately.
- **Ready-made UI.** `PaywallSheet` and `CustomerCenterSheet` present the right RevenueCatUI surface for each platform: `fullScreenCover` for the paywall on iOS, a sized `sheet` on macOS, and an App Store subscriptions deep link for customer management on macOS.

## Installation

**Xcode.** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall`. Add the products you need:

- `SwiduxRevenueCatPaywall` — the `PaywallService` implementation and mock.
- `SwiduxRevenueCatPaywallUI` — adds the `PaywallSheet` and `CustomerCenterSheet` views (depends on RevenueCatUI).

**Package.swift.**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall", branch: "main"),
```

```swift
.product(name: "SwiduxRevenueCatPaywall", package: "SwiduxRevenueCatPaywall"),
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"), // optional
```

## Quickstart

### 1. Configure RevenueCat at launch

`RevenueCatPaywallService` calls into `Purchases.shared`, so configure the SDK before the store is constructed.

```swift
import RevenueCat

Purchases.configure(withAPIKey: "your_revenuecat_api_key")
```

### 2. Register the paywall plugin

Pass `RevenueCatPaywallService` to `PaywallPlugin` when wiring your `Store`.

```swift
import Swidux
import SwiduxPaywall
import SwiduxRevenueCatPaywall

plugins.register(
    PaywallPlugin(
        state: \.paywall,
        action: AppAction.paywall,
        extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
        service: RevenueCatPaywallService(entitlementID: "pro")
    )
)
```

Gate pro features by checking `store.paywall.isGateSatisfied`. See [Add a Paywall](https://heirloomlogic.github.io/Swidux/documentation/swidux/howtoaddapaywall) for the full plugin contract.

### 3. Attach the UI

Add `PaywallSheet` and `CustomerCenterSheet` to a root view, driven by paywall state.

```swift
import SwiduxRevenueCatPaywallUI

struct RootView: View {
    @Bindable var store: AppStore

    var body: some View {
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
    }
}
```

## Previews and tests

Use `MockRevenueCatPaywallService` to drive entitlement state without contacting RevenueCat. `send(_:)` pushes a snapshot to active stream subscribers; `finish()` ends the stream.

```swift
import SwiduxPaywall
import SwiduxRevenueCatPaywall

let mock = MockRevenueCatPaywallService(isPro: false)

// Later — simulate a successful purchase.
mock.send(EntitlementSnapshot(isPro: true, hasPermanentLicense: false))
```

Wire it into the plugin the same way as the live service:

```swift
PaywallPlugin(
    state: \.paywall,
    action: AppAction.paywall,
    extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
    service: MockRevenueCatPaywallService(isPro: true)
)
```

## Permanent license

For apps that sell a lifetime entitlement alongside a subscription, pass a second identifier:

```swift
RevenueCatPaywallService(
    entitlementID: "pro",
    permanentLicenseEntitlementID: "lifetime"
)
```

Both entitlements are checked on every `customerInfo()`, `customerInfoStream()`, and `restorePurchases()` call. The lifetime entitlement surfaces as `EntitlementSnapshot.hasPermanentLicense`, leaving `isPro` to track the subscription independently.

## Platform notes

- **iOS.** `PaywallSheet` presents `RevenueCatUI.PaywallView` in a `fullScreenCover`. `CustomerCenterSheet` presents `RevenueCatUI.CustomerCenterView` in a sheet.
- **macOS.** `PaywallSheet` presents `PaywallView` in a sheet sized to a 400×600 minimum. `CustomerCenterSheet` does not present a view — it opens `itms-apps://apps.apple.com/account/subscriptions` in App Store and immediately calls `onDismiss`, since RevenueCat's customer center is iOS-only.

## Requirements

- Swift 6.2
- iOS 18 / macOS 15
- [Swidux](https://github.com/HeirloomLogic/Swidux) (`SwiduxPaywall` product)
- [RevenueCat](https://github.com/RevenueCat/purchases-ios-spm) 5.0+

## License

MIT
