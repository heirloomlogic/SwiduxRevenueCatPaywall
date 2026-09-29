# Platform Behavior

How the `revenueCatPaywall` and `revenueCatCustomerCenter` modifiers choose presentation, and which controls remain fixed.

## Overview

The bundled UI chooses a platform-appropriate default while exposing the iOS presentation style. The same `.paywall(.dismiss)` action fires from every presentation.

This article explains the reasoning behind those choices and what is fixed versus configurable.

## revenueCatPaywall

| Platform | Presentation | Reason |
|---|---|---|
| **iOS, compact width** | `fullScreenCover` | Compact screens keep the paywall immersive and avoid a cramped sheet. |
| **iOS, regular width** | `sheet` | iPad and other regular-width hosts follow RevenueCatUI's sheet default. |
| **macOS** | `sheet` with `frame(minWidth: 400, minHeight: 600)` | Mac sheets do not expand to fill the parent window. Without an explicit minimum size the paywall would render too small to legibly show plan options. The 400×600 minimum is roughly the size RevenueCatUI's templates assume. |

The `.automatic` style uses the table above. iOS callers can force `.sheet` or `.fullScreen`; macOS always uses a sheet. The modifiers show `PaywallView`'s close button by default. On macOS, Escape clears the presentation binding only when the close button is enabled. Pass `displayCloseButton: false` only for a hard paywall the user must purchase through.

The minimum frame is hard-coded; it is not exposed as a parameter. If your paywall layout needs more room on macOS, use `RevenueCatUI.PaywallView` directly inside a custom `sheet` modifier.

## revenueCatCustomerCenter

| Platform | Presentation | Reason |
|---|---|---|
| **iOS** | `sheet` with `RevenueCatUI.CustomerCenterView` | RevenueCatUI ships a customer center on iOS only. A non-fullscreen `sheet` is appropriate because customer-center actions are administrative, not part of a purchase flow. |
| **macOS** | Opens `itms-apps://apps.apple.com/account/subscriptions`, then clears the request | RevenueCatUI does not ship a customer center on macOS, and the system has no equivalent in-app surface. The primitive modifier uses SwiftUI's URL opener and fires `onDismiss`; the composed modifier dispatches the plugin's `.openManageSubscriptions` and `.dismissCustomerCenter` actions. |

With the composed modifier, the macOS branch dispatches `.openManageSubscriptions` through `PaywallPlugin`, then clears the binding to dispatch `.dismissCustomerCenter`. The plugin's URL opener is injectable, so apps and tests can control the external hand-off. The primitive binding-based modifier uses SwiftUI's `openURL` environment action and falls back to `https://apps.apple.com/account/subscriptions` when nothing handles the `itms-apps` scheme.

## Presentation coordination

On iOS, the composed `revenueCatPaywall(state:offeringIdentifier:displayCloseButton:fonts:presentationStyle:purchaseLogic:onEvent:send:)` modifier never shows the paywall and customer center at once. The paywall wins: while `PaywallState.isPresented` is `true`, the customer-center binding reads `false`, and an initial or later state with both flags set dispatches `.dismissCustomerCenter`.

On macOS, subscription management is an external App Store hand-off rather than a second modal surface. The customer-center binding remains active while the paywall sheet is open, so the composed modifier dispatches `.openManageSubscriptions` and then `.dismissCustomerCenter` without losing the request.

Apps wiring the primitive modifiers manually own the iOS exclusivity rule.

## One app-wide attachment

Attach the composed modifier once, to one app-wide presentation host. `PaywallState` is shared, so attaching the modifier inside every `WindowGroup` window or scene makes every copy respond to the same request. A multi-window app should choose one scene, such as its primary app or settings window, to own paywall presentation.

## Exit offers

RevenueCat dashboard exit offers are unavailable through the bundled modifiers. RevenueCatUI implements exit offers in its own presentation modifiers, which always add a close button. This package embeds `PaywallView` so `displayCloseButton: false` remains a hard paywall. Use RevenueCatUI's presenter directly when exit offers are required.

## What is configurable

The configurable surface lives in `RevenueCatUI` and on the paywall plugin:

- **Paywall content, copy, and template** — configured in the RevenueCat dashboard. `RevenueCatUI.PaywallView` renders whichever offering and template the dashboard returns.
- **Customer-center labels, sections, and actions** — configured in the RevenueCat dashboard. `RevenueCatUI.CustomerCenterView` renders whichever configuration the dashboard returns.
- **Close button** — `displayCloseButton:` on the paywall modifiers. Defaults to `true`; pass `false` for a hard paywall.
- **Fonts** — `fonts:` accepts any RevenueCatUI `PaywallFontProvider`.
- **Presentation** — `presentationStyle:` controls iOS sheet or full-screen presentation; `.automatic` follows horizontal size class.
- **Outcomes** — `onEvent:` reports package-owned purchase, restore, cancellation, and failure values from inside the presentation boundary.
- **Presentation triggering** — driven by the plugin via `PaywallState.isPresented` and `isCustomerCenterPresented`. Your code chooses *when* to set them via `.request(reason:)` and `.presentCustomerCenter` actions.
- **Dismiss behavior** — dismiss actions are dispatched by the presentation bindings themselves (`.dismiss` for the paywall, `.dismissCustomerCenter` for the customer center). The primitive modifiers' `onDismiss` callbacks are purely additive — use them for analytics hooks or cleanup, not for dispatch.
- **Offering selection** — `offeringIdentifier:` presents a specific offering and takes precedence over placement targeting. The composed modifier otherwise passes `PaywallState.requestedReason` as a RevenueCat placement. Missing placements and fetch failures fall back to the current offering; an unknown explicit identifier also asserts in Debug and logs a warning.

## See Also

- <doc:HowToPresentTheUI>

The `SwiduxRevenueCatPaywallUI` documentation provides the matching API reference for the modifiers described here.
