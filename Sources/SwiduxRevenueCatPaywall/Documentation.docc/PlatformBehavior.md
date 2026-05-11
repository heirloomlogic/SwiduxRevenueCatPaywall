# Platform Behavior

Why the `revenueCatPaywall` and `revenueCatCustomerCenter` modifiers present differently on iOS and macOS, and what is hard-coded.

## Overview

The bundled UI is intentionally opinionated. Each modifier picks the platform-appropriate presentation so consumers don't have to repeat the conditional compilation themselves, and so the dispatch flow stays symmetric across platforms — the same `.paywall(.dismiss)` action fires from a `fullScreenCover` on iOS and from a sheet on macOS.

This article explains the reasoning behind those choices and what is fixed versus configurable.

## revenueCatPaywall

| Platform | Presentation | Reason |
|---|---|---|
| **iOS** | `fullScreenCover` | A subscription paywall is a primary moment, not an interrupt. `fullScreenCover` keeps the UI immersive, prevents accidental gesture-dismiss, and matches App Store conventions. |
| **macOS** | `sheet` with `frame(minWidth: 400, minHeight: 600)` | Mac sheets do not expand to fill the parent window. Without an explicit minimum size the paywall would render too small to legibly show plan options. The 400×600 minimum is roughly the size RevenueCatUI's templates assume. |

The minimum frame is hard-coded; it is not exposed as a parameter. If your paywall layout needs more room on macOS, wrap the modified view in a parent that imposes a larger frame, or use `RevenueCatUI.PaywallView` directly inside a custom `sheet` modifier.

## revenueCatCustomerCenter

| Platform | Presentation | Reason |
|---|---|---|
| **iOS** | `sheet` with `RevenueCatUI.CustomerCenterView` | RevenueCatUI ships a customer center on iOS only. A non-fullscreen `sheet` is appropriate because customer-center actions are administrative, not part of a purchase flow. |
| **macOS** | Opens `itms-apps://apps.apple.com/account/subscriptions` and immediately fires `onDismiss` | RevenueCatUI does not ship a customer center on macOS, and the system has no equivalent in-app surface. The App Store subscription management page is what users expect on the Mac, so the sheet hands off to it and clears its own presentation state immediately. |

The macOS branch clears the binding and fires `onDismiss` synchronously after `NSWorkspace.shared.open` so `PaywallState.isCustomerCenterPresented` does not get stuck `true`. The user returns from App Store to find the app's UI in its idle state.

## Why no platform-override hooks

Both modifiers are deliberately parameter-light: an `isPresented: Binding<Bool>` and an optional `onDismiss: () -> Void`. There is no `paywallStyle:` or `presentationKind:` parameter.

The reasoning: any consumer that needs to deviate from the chosen presentation already has the underlying RevenueCatUI types (`PaywallView`, `CustomerCenterView`) and SwiftUI's full presentation surface (`sheet`, `fullScreenCover`, `popover`, custom containers). The bundled modifiers exist to handle the 95% case in one line — when the 5% case applies, drop down to RevenueCatUI directly.

This package does not try to be the complete paywall-UI library. It is the *integration layer* that makes the common case trivial.

## What is configurable

The configurable surface lives in `RevenueCatUI` and on the paywall plugin:

- **Paywall content, copy, and template** — configured in the RevenueCat dashboard. `RevenueCatUI.PaywallView` renders whichever offering and template the dashboard returns.
- **Customer-center labels, sections, and actions** — configured in the RevenueCat dashboard. `RevenueCatUI.CustomerCenterView` renders whichever configuration the dashboard returns.
- **Presentation triggering** — driven by the plugin via `PaywallState.isPresented` and `isCustomerCenterPresented`. Your code chooses *when* to set them via `.request(reason:)` and `.presentCustomerCenter` actions.
- **Dismiss behavior** — your `onDismiss` closures dispatch the matching paywall actions. Replace them if you need analytics hooks or cleanup beyond the default flow.

## See Also

- <doc:HowToPresentTheUI>

The `SwiduxRevenueCatPaywallUI` documentation provides the matching API reference for the modifiers described here.
