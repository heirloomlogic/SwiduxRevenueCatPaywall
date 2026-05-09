# ``SwiduxRevenueCatPaywallUI``

Drop-in SwiftUI views and a view modifier that present RevenueCatUI's paywall and customer center, driven by `PaywallState` from Swidux's paywall plugin.

@Metadata {
    @DisplayName("SwiduxRevenueCatPaywallUI")
}

## Overview

`SwiduxRevenueCatPaywallUI` is the UI half of the RevenueCat adapter for Swidux. It layers two stateless SwiftUI views and a convenience modifier on top of `RevenueCatUI`. Each view is bound to `PaywallState`: the relevant presentation flag drives visibility, and a dismissal closure dispatches the matching paywall action back through the store. There is no local sheet state and no provider configuration.

For the integration narrative — installing the package, configuring RevenueCat, registering the plugin, and wiring the views — start with the `SwiduxRevenueCatPaywall` documentation. *Getting Started* there is the canonical entry point; *How to Present the UI* covers the views in detail.

## Topics

### Reference

- <doc:UIComponentsReference>

### UI Components

- ``PaywallSheet``
- ``CustomerCenterSheet``
