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

### `revenueCatPaywall(isPresented:offeringIdentifier:displayCloseButton:fonts:presentationStyle:purchaseLogic:onEvent:onDismiss:)`

```swift
extension View {
    public func revenueCatPaywall(
        isPresented: Binding<Bool>,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        presentationStyle: RevenueCatPaywallPresentationStyle = .automatic,
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View
}
```

Attaches `RevenueCatUI.PaywallView` as a platform-appropriate sheet.

- **iOS** — The automatic style uses a full-screen cover at compact width and a sheet at regular width.
- **macOS** — Presents in a `sheet` sized to a 400×600 minimum.

Pass a real two-way binding; SwiftUI sets it to `false` on user dismissal. Build it from `PaywallState.isPresented` so the `set:` closure dispatches `.paywall(.dismiss)` and the plugin clears its presentation state.

#### Parameters

- `isPresented` — Two-way binding to the paywall's visibility flag.
- `offeringIdentifier` — Identifier of the RevenueCat offering to present, for a win-back or regional offer. Defaults to `nil`, which presents the dashboard's current offering. An unknown identifier asserts in Debug and falls back to the current offering with a logged warning; a fetch failure also falls back without asserting.
- `displayCloseButton` — Whether `PaywallView` shows a close button. Defaults to `true`. On macOS, Escape dismisses only when this is `true`.
- `fonts` — RevenueCatUI font provider used by every resolved paywall.
- `presentationStyle` — `.automatic` adapts to iOS width and uses a sheet on macOS. iOS callers can force `.sheet` or `.fullScreen`.
- `purchaseLogic` — App-owned StoreKit 2 purchase and restore operations for `purchasesAreCompletedBy: .myApp`. Leave `nil` when RevenueCat completes purchases.
- `onEvent` — Optional callback for package-owned purchase, restore, cancellation, purchase-failure, and restore-failure values. It exposes Foundation identifiers and error fields instead of RevenueCat models.
- `onDismiss` — Optional callback fired after dismissal.

Dashboard exit offers do not run through these modifiers. RevenueCatUI implements them in its own `presentPaywall` modifiers, which always add a close button; using that path here would change `displayCloseButton: false` from a hard paywall into a dismissible one. Apps that need exit offers should use RevenueCatUI's presenter directly.

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
- **macOS** — Opens `itms-apps://apps.apple.com/account/subscriptions` through SwiftUI's `openURL` environment action (falling back to the `https://apps.apple.com/account/subscriptions` web URL if nothing handles the `itms-apps` scheme), immediately clears the binding, and fires `onDismiss`. RevenueCatUI does not ship a customer center on macOS.

#### Parameters

- `isPresented` — Two-way binding to the customer center's visibility flag.
- `onDismiss` — Optional callback fired after dismissal (or, on macOS, after the App Store URL is opened).

### `revenueCatPaywall(state:offeringIdentifier:displayCloseButton:fonts:presentationStyle:purchaseLogic:onEvent:send:)`

```swift
extension View {
    public func revenueCatPaywall(
        state: PaywallState,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        presentationStyle: RevenueCatPaywallPresentationStyle = .automatic,
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        send: @escaping (PaywallAction) -> Void
    ) -> some View
}
```

Convenience modifier that attaches both primitive presentation surfaces and dispatches the matching actions through `send`.

On iOS the two presentations are mutually exclusive and the paywall wins. On macOS a customer-center request dispatches `.openManageSubscriptions` through the paywall plugin, then `.dismissCustomerCenter`; the external App Store hand-off remains available while the paywall sheet is open. After a restore inside the paywall, the modifier also dispatches `.dismiss` once `state.isGateSatisfied` is `true`, because RevenueCatUI does not dismiss after a restore. Attach the modifier once to one app-wide presentation host. See *Platform Behavior* in the `SwiduxRevenueCatPaywall` documentation.

#### Parameters

- `state` — The paywall slice from your store, typically `store.paywall`.
- `offeringIdentifier` — Identifier of the RevenueCat offering to present. When it is `nil`, `state.requestedReason` is used as a RevenueCat placement identifier; a placement with no targeted offering falls back to the dashboard's current offering. An explicit identifier takes precedence.
- `displayCloseButton` — Whether `PaywallView` shows a close button. Defaults to `true`; see the primitive modifier above.
- `fonts` — RevenueCatUI font provider used by the paywall.
- `presentationStyle` — Automatic or explicit iOS presentation style; macOS always uses a sheet.
- `purchaseLogic` — App-owned StoreKit 2 purchase and restore operations for `purchasesAreCompletedBy: .myApp`. Leave `nil` when RevenueCat completes purchases.
- `onEvent` — Optional package-owned outcome callback; see the primitive modifier above.
- `send` — A closure that lifts a `PaywallAction` into your root action and dispatches it through the store. Typically `{ store.send(.paywall($0)) }`.

#### Manual wiring

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

This attaches the same presentation surfaces but leaves the iOS exclusivity and close-after-restore rules to the app. Use the convenience modifier when both surfaces are needed; use the primitives when only one is needed or when you want to interleave other modifiers between them.

## See Also

- <doc:HowToPresentTheUI>
- <doc:PlatformBehavior>
