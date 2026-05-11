# UI Components Reference

API reference for the `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers — the SwiftUI surface of `SwiduxRevenueCatPaywallUI`.

## Overview

The UI product layers three view modifiers on top of `RevenueCatUI`. Two primitives present the paywall and customer center directly from a `Binding<Bool>`; one convenience modifier composes both, driven by `PaywallState`. Each presentation modifier attaches to the modified content view directly — there are no `View` wrappers and no `.background { … }` indirection. This shape is what makes the macOS sheet machinery present reliably.

For step-by-step wiring, see *How to Present the UI* in the `SwiduxRevenueCatPaywall` documentation. For the rationale behind platform-specific behavior, see *Platform Behavior* in the same catalog.

## Library target

- Product: `SwiduxRevenueCatPaywallUI`
- Import: `import SwiduxRevenueCatPaywallUI`

`Package.swift`:

```swift
.product(name: "SwiduxRevenueCatPaywallUI", package: "SwiduxRevenueCatPaywall"),
```

The UI product depends on `SwiduxRevenueCatPaywall` and `RevenueCatUI`, both pulled in transitively. Apps that don't ship paywall UI in the same target (for example, a tests-only target) can depend on the lower-level `SwiduxRevenueCatPaywall` product alone.

## Modifiers

### `revenueCatPaywall(isPresented:onDismiss:)`

```swift
extension View {
    public func revenueCatPaywall(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil
    ) -> some View
}
```

Attaches `RevenueCatUI.PaywallView` as a platform-appropriate sheet.

- **iOS** — Presents in a `fullScreenCover` so the paywall takes the full screen.
- **macOS** — Presents in a `sheet` sized to a 400×600 minimum.

Pass a real two-way binding; SwiftUI sets it to `false` on user dismissal. Build it from `PaywallState.isPresented` so the `set:` closure dispatches `.paywall(.dismiss)` and the plugin clears its presentation state.

#### Parameters

- `isPresented` — Two-way binding to the paywall's visibility flag.
- `onDismiss` — Optional callback fired after dismissal.

### `revenueCatCustomerCenter(isPresented:onDismiss:)`

```swift
extension View {
    public func revenueCatCustomerCenter(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil
    ) -> some View
}
```

Attaches the customer center as a platform-appropriate sheet.

- **iOS** — Presents `RevenueCatUI.CustomerCenterView` in a `sheet`.
- **macOS** — Opens `itms-apps://apps.apple.com/account/subscriptions` via `NSWorkspace.shared.open`, immediately clears the binding, and fires `onDismiss`. RevenueCatUI does not ship a customer center on macOS.

#### Parameters

- `isPresented` — Two-way binding to the customer center's visibility flag.
- `onDismiss` — Optional callback fired after dismissal (or, on macOS, after the App Store URL is opened).

### `revenueCatPaywall(state:send:)`

```swift
extension View {
    public func revenueCatPaywall(
        state: PaywallState,
        send: @escaping (PaywallAction) -> Void
    ) -> some View
}
```

Convenience modifier that attaches both `revenueCatPaywall(isPresented:onDismiss:)` and `revenueCatCustomerCenter(isPresented:onDismiss:)` and dispatches the matching dismiss action when each sheet closes.

#### Parameters

- `state` — The paywall slice from your store, typically `store.paywall`.
- `send` — A closure that lifts a `PaywallAction` into your root action and dispatches it through the store. Typically `{ store.send(.paywall($0)) }`.

#### Equivalent manual wiring

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

Use the convenience modifier when both sheets are needed; use the primitives when only one is needed or when you want to interleave other modifiers between them.

## See Also

- <doc:HowToPresentTheUI>
- <doc:PlatformBehavior>
