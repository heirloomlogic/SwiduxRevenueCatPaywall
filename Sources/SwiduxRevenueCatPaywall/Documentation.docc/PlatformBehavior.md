# Platform Behavior

Why the `revenueCatPaywall` and `revenueCatCustomerCenter` modifiers present differently on iOS and macOS, and what is hard-coded.

## Overview

The bundled UI is intentionally opinionated. Each modifier picks the platform-appropriate presentation so consumers don't have to repeat the conditional compilation themselves, and so the dispatch flow stays symmetric across platforms — the same `.paywall(.dismiss)` action fires from a `fullScreenCover` on iOS and from a sheet on macOS.

This article explains the reasoning behind those choices and what is fixed versus configurable.

## revenueCatPaywall

| Platform | Presentation | Reason |
|---|---|---|
| **iOS** | `fullScreenCover` | A subscription paywall is a primary moment, not an interrupt. `fullScreenCover` keeps the UI immersive and prevents accidental gesture-dismiss. |
| **macOS** | `sheet` with `frame(minWidth: 400, minHeight: 600)` | Mac sheets do not expand to fill the parent window. Without an explicit minimum size the paywall would render too small to legibly show plan options. The 400×600 minimum is roughly the size RevenueCatUI's templates assume. |

Because neither presentation offers a system dismissal affordance (`fullScreenCover` has no swipe-to-dismiss; Mac sheets have no default close control), the modifiers show `PaywallView`'s close button by default. Pass `displayCloseButton: false` only for a hard paywall the user must purchase through — and make sure some other path out of that screen exists.

The minimum frame is hard-coded; it is not exposed as a parameter. If your paywall layout needs more room on macOS, use `RevenueCatUI.PaywallView` directly inside a custom `sheet` modifier.

## revenueCatCustomerCenter

| Platform | Presentation | Reason |
|---|---|---|
| **iOS** | `sheet` with `RevenueCatUI.CustomerCenterView` | RevenueCatUI ships a customer center on iOS only. A non-fullscreen `sheet` is appropriate because customer-center actions are administrative, not part of a purchase flow. |
| **macOS** | Opens `itms-apps://apps.apple.com/account/subscriptions`, then clears the request | RevenueCatUI does not ship a customer center on macOS, and the system has no equivalent in-app surface. The primitive modifier uses SwiftUI's URL opener and fires `onDismiss`; the composed modifier dispatches the plugin's `.openManageSubscriptions` and `.dismissCustomerCenter` actions. |

With the composed modifier, the macOS branch dispatches `.openManageSubscriptions` through `PaywallPlugin`, then clears the binding to dispatch `.dismissCustomerCenter`. The plugin's URL opener is injectable, so apps and tests can control the external hand-off. The primitive binding-based modifier uses SwiftUI's `openURL` environment action and falls back to `https://apps.apple.com/account/subscriptions` when nothing handles the `itms-apps` scheme.

## Presentation coordination

On iOS, the composed `revenueCatPaywall(state:offeringIdentifier:displayCloseButton:purchaseLogic:send:)` modifier never shows the paywall and customer center at once. The paywall wins: while `PaywallState.isPresented` is `true`, the customer-center binding reads `false`, and an initial or later state with both flags set dispatches `.dismissCustomerCenter`.

On macOS, subscription management is an external App Store hand-off rather than a second modal surface. The customer-center binding remains active while the paywall sheet is open, so the composed modifier dispatches `.openManageSubscriptions` and then `.dismissCustomerCenter` without losing the request.

Apps wiring the primitive modifiers manually own the iOS exclusivity rule.

## One app-wide attachment

Attach the composed modifier once, to one app-wide presentation host. `PaywallState` is shared, so attaching the modifier inside every `WindowGroup` window or scene makes every copy respond to the same request. A multi-window app should choose one scene, such as its primary app or settings window, to own paywall presentation.

## Why no platform-override hooks

Both modifiers are deliberately parameter-light: an `isPresented: Binding<Bool>`, an optional `onDismiss: () -> Void`, and — on the paywall only — `displayCloseButton:`, `offeringIdentifier:`, and optional app-owned `purchaseLogic:`. There is no `paywallStyle:` or `presentationKind:` parameter.

The reasoning: any consumer that needs to deviate from the chosen presentation already has the underlying RevenueCatUI types (`PaywallView`, `CustomerCenterView`) and SwiftUI's full presentation surface (`sheet`, `fullScreenCover`, `popover`, custom containers). The bundled modifiers exist to handle the 95% case in one line — when the 5% case applies, drop down to RevenueCatUI directly.

This package does not try to be the complete paywall-UI library. It is the *integration layer* that makes the common case trivial.

## What is configurable

The configurable surface lives in `RevenueCatUI` and on the paywall plugin:

- **Paywall content, copy, and template** — configured in the RevenueCat dashboard. `RevenueCatUI.PaywallView` renders whichever offering and template the dashboard returns.
- **Customer-center labels, sections, and actions** — configured in the RevenueCat dashboard. `RevenueCatUI.CustomerCenterView` renders whichever configuration the dashboard returns.
- **Close button** — `displayCloseButton:` on the paywall modifiers. Defaults to `true`; pass `false` for a hard paywall.
- **Presentation triggering** — driven by the plugin via `PaywallState.isPresented` and `isCustomerCenterPresented`. Your code chooses *when* to set them via `.request(reason:)` and `.presentCustomerCenter` actions.
- **Dismiss behavior** — dismiss actions are dispatched by the presentation bindings themselves (`.dismiss` for the paywall, `.dismissCustomerCenter` for the customer center). The primitive modifiers' `onDismiss` callbacks are purely additive — use them for analytics hooks or cleanup, not for dispatch.
- **Offering selection** — `offeringIdentifier:` on the paywall modifiers presents a specific RevenueCat offering (a win-back or regional offer, for example). Omit it for the dashboard's current offering. An unknown identifier or a failed fetch falls back to the current offering with a logged warning, so a stale identifier degrades gracefully instead of dead-ending the purchase flow.

## See Also

- <doc:HowToPresentTheUI>

The `SwiduxRevenueCatPaywallUI` documentation provides the matching API reference for the modifiers described here.
