# UI Components Reference

API reference for `PaywallSheet`, `CustomerCenterSheet`, and the `revenueCatPaywall(state:send:)` view modifier — the SwiftUI surface of `SwiduxRevenueCatPaywallUI`.

## Overview

The UI product layers two `View` types and a convenience modifier on top of `RevenueCatUI`. Each is a stateless wrapper bound to `PaywallState`: presentation flags drive visibility, and dismissal closures dispatch matching paywall actions back through the store.

For step-by-step wiring, see *How to Present the UI* in the `SwiduxRevenueCatPaywall` documentation. For the rationale behind platform-specific behavior, see *Platform Behavior* in the same catalog.

## Library target

- Product: `SwiduxRevenueCatPaywallUI`
- Import: `import SwiduxRevenueCatPaywallUI`

`Package.swift`:

```swift
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
```

The UI product depends on `SwiduxRevenueCatPaywall` and `RevenueCatUI`, both pulled in transitively. Apps that don't ship paywall UI in the same target (for example, a tests-only target) can depend on the lower-level `SwiduxRevenueCatPaywall` product alone.

## Types

### `PaywallSheet`

```swift
public struct PaywallSheet: View {
    public init(isPresented: Bool, onDismiss: @escaping () -> Void)
}
```

Wraps `RevenueCatUI.PaywallView`.

- **iOS** — Presents in a `fullScreenCover` so the paywall takes the full screen.
- **macOS** — Presents in a `sheet` sized to a 400×600 minimum.

Place anywhere in the view tree; the body is `EmptyView` plus the platform-appropriate presentation modifier, so attaching via `.background` keeps it out of layout.

#### Initializer

- `isPresented` — Whether the sheet is visible. Pass `store.paywall.isPresented` directly. The plugin owns this flag.
- `onDismiss` — Called when the user dismisses the sheet. Dispatch `.paywall(.dismiss)` so the plugin clears its presentation state and triggers an entitlement refresh.

### `CustomerCenterSheet`

```swift
public struct CustomerCenterSheet: View {
    public init(isPresented: Bool, onDismiss: @escaping () -> Void)
}
```

Adapts to platform support for RevenueCat's customer center.

- **iOS** — Presents `RevenueCatUI.CustomerCenterView` in a `sheet`.
- **macOS** — Opens `itms-apps://apps.apple.com/account/subscriptions` via `NSWorkspace.shared.open` and immediately fires `onDismiss`. RevenueCatUI does not ship a customer center on macOS.

#### Initializer

- `isPresented` — Whether the sheet is visible. Pass `store.paywall.isCustomerCenterPresented` directly.
- `onDismiss` — Called when the user dismisses the sheet (or, on macOS, immediately after the App Store URL is opened). Dispatch `.paywall(.dismissCustomerCenter)` so the plugin clears its presentation state.

### `revenueCatPaywall(state:send:)`

```swift
extension View {
    public func revenueCatPaywall(
        state: PaywallState,
        send: @escaping (PaywallAction) -> Void
    ) -> some View
}
```

Convenience modifier that attaches both `PaywallSheet` and `CustomerCenterSheet` and dispatches the matching dismiss action when each sheet closes.

#### Parameters

- `state` — The paywall slice from your store, typically `store.paywall`.
- `send` — A closure that lifts a `PaywallAction` into your root action and dispatches it through the store. Typically `{ store.send(.paywall($0)) }`.

#### Equivalent manual wiring

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

Use the modifier when both sheets are needed; use the manual form when only one is needed or when you want to interleave other modifiers between them.

## See Also

- <doc:HowToPresentTheUI>
- <doc:PlatformBehavior>
