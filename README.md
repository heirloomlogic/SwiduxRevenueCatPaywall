# SwiduxRevenueCatPaywall

**RevenueCat adapter for Swidux's `PaywallPlugin`.** Implements `PaywallService` against `Purchases.shared`, ships a controllable mock for previews and tests, and provides drop-in SwiftUI view modifiers that wrap RevenueCatUI's `PaywallView` and `CustomerCenterView` with platform-aware presentation.

## Why this package

- **Drop-in `PaywallService` conformance.** `RevenueCatPaywallService` maps `CustomerInfo` to Swidux's `EntitlementSnapshot` and forwards `customerInfoStream` so the plugin sees real-time entitlement changes.
- **Optional permanent-license entitlement.** A second entitlement ID can be checked alongside the standard pro entitlement and surfaces as `EntitlementSnapshot.hasPermanentLicense`.
- **Preview- and test-friendly mock.** `MockRevenueCatPaywallService` exposes `send(_:)` and `finish()` so tests and previews can drive entitlement transitions over time — unlike `MockPaywallService` from SwiduxPaywall, which finishes its stream immediately.
- **Ready-made UI.** The `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers present the right RevenueCatUI surface for each platform: `fullScreenCover` for the paywall on iOS, a sized `sheet` on macOS, and an App Store subscriptions deep link for customer management on macOS.

## Installation

**Xcode.** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall`. Add the products you need:

- `SwiduxRevenueCatPaywall` — the `PaywallService` implementation and mock.
- `SwiduxRevenueCatPaywallUI` — adds the `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers (depends on RevenueCatUI).

**Package.swift.**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall", from: "1.0.0"),
```

```swift
.product(name: "SwiduxRevenueCatPaywall", package: "SwiduxRevenueCatPaywall"),
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"), // optional
```

## Quickstart

Configure the paywall at launch, register the paywall plugin with `RevenueCatPaywallService`, and attach the bundled UI:

```swift
import Swidux
import SwiduxPaywall
import SwiduxRevenueCatPaywall
import SwiduxRevenueCatPaywallUI

// 1. App launch
RevenueCatPaywall.configure(apiKey: "your_revenuecat_api_key")

// 2. Plugin registration
plugins.register(
    PaywallPlugin(
        state: \.paywall,
        action: AppAction.paywall,
        extractAction: { if case .paywall(let a) = $0 { return a }; return nil },
        service: RevenueCatPaywallService(entitlementID: "pro")
    )
)

// 3. UI
ContentView()
    .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
```

Gate features by reading `store.paywall.isGateSatisfied`. Trigger the paywall with `store.send(.paywall(.request(reason: "...")))`. See the [Getting Started](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/gettingstarted) guide for the full walk-through.

## Documentation

Full DocC reference at https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/. Starting points by intent:

- **I want the shortest path to a working paywall** — [Getting Started](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/gettingstarted)
- **I want to wire the service step by step** — [How to Implement the Service](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/howtoimplementservice)
- **I sell a lifetime SKU alongside a subscription** — [How to Add a Permanent License](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/howtoaddapermanentlicense)
- **I want to preview / test without RevenueCat** — [How to Preview and Test](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/howtopreviewandtest)
- **I want to wire the bundled view modifiers** — [How to Present the UI](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/howtopresenttheui)
- **I want the API** — [Service Reference](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/servicereference), [Mock Service Reference](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/mockservicereference), [UI Components Reference](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywallui/uicomponentsreference)
- **I want to understand the design choices** — [Platform Behavior](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/platformbehavior), [Entitlement Mapping](https://heirloomlogic.github.io/SwiduxRevenueCatPaywall/documentation/swiduxrevenuecatpaywall/entitlementmapping)

## Requirements

- Swift 6.2 / Xcode 26+
- iOS 18 / macOS 15
- [Swidux](https://github.com/HeirloomLogic/Swidux) (`SwiduxPaywall` product)
- [RevenueCat](https://github.com/RevenueCat/purchases-ios-spm) 5.0+

## License

MIT — see [LICENSE](LICENSE).
