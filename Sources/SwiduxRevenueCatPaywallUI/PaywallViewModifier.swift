//
//  PaywallViewModifier.swift
//  SwiduxRevenueCatPaywallUI
//

import RevenueCatUI
import SwiduxPaywall
import SwiftUI

#if !os(iOS) && !os(macOS)
#error("SwiduxRevenueCatPaywallUI supports iOS and macOS only.")
#endif

/// Attaches `RevenueCatUI.PaywallView` to the modified view, driven by a `Binding<Bool>`.
///
/// Presents in a `fullScreenCover` on iOS and a 400×600-minimum `sheet` on macOS.
struct RevenueCatPaywallSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let displayCloseButton: Bool
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
            PaywallView(displayCloseButton: displayCloseButton)
        }
        #else
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            PaywallView(displayCloseButton: displayCloseButton)
                .frame(minWidth: 400, minHeight: 600)
        }
        #endif
    }
}

/// Attaches `RevenueCatUI.CustomerCenterView` (iOS) or an App Store hand-off (macOS) to the
/// modified view, driven by a `Binding<Bool>`.
struct RevenueCatCustomerCenterSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            CustomerCenterView()
        }
        #else
        content.onChange(of: isPresented) { _, presented in
            guard presented else { return }
            Self.openSubscriptionManagement()
            isPresented = false
            onDismiss?()
        }
        #endif
    }

    #if os(macOS)
    /// Opens App Store subscription management, falling back to the web URL when nothing on
    /// the system claims the `itms-apps` scheme.
    static func openSubscriptionManagement() {
        let appStore = URL(string: "itms-apps://apps.apple.com/account/subscriptions")
        if let appStore, NSWorkspace.shared.open(appStore) { return }
        if let web = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(web)
        }
    }
    #endif
}

/// Composes paywall and customer-center sheets onto a view, driven by `PaywallState`.
struct RevenueCatPaywallModifier: ViewModifier {
    let state: PaywallState
    let displayCloseButton: Bool
    let send: (PaywallAction) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(
                RevenueCatPaywallSheetModifier(
                    isPresented: paywallBinding,
                    displayCloseButton: displayCloseButton,
                    onDismiss: nil
                )
            )
            .modifier(
                RevenueCatCustomerCenterSheetModifier(
                    isPresented: customerCenterBinding,
                    onDismiss: nil
                )
            )
    }

    var paywallBinding: Binding<Bool> {
        Binding(
            get: { state.isPresented },
            set: { newValue in if !newValue { send(.dismiss) } }
        )
    }

    var customerCenterBinding: Binding<Bool> {
        Binding(
            get: { state.isCustomerCenterPresented },
            set: { newValue in if !newValue { send(.dismissCustomerCenter) } }
        )
    }
}

extension View {
    /// Attaches the RevenueCat paywall as a platform-appropriate sheet.
    ///
    /// Presents `RevenueCatUI.PaywallView` in a `fullScreenCover` on iOS and a 400×600-minimum
    /// `sheet` on macOS. The binding's setter is called with `false` when the user dismisses,
    /// so wire it to clear `PaywallState.isPresented` (typically by dispatching `.paywall(.dismiss)`).
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(
    ///         isPresented: Binding(
    ///             get: { store.paywall.isPresented },
    ///             set: { if !$0 { store.send(.paywall(.dismiss)) } }
    ///         )
    ///     )
    /// ```
    ///
    /// See ``revenueCatPaywall(state:displayCloseButton:send:)`` for the convenience overload
    /// that builds the binding for you.
    ///
    /// - Parameters:
    ///   - isPresented: Two-way binding to the paywall's visibility flag.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`;
    ///     neither the iOS `fullScreenCover` nor the macOS `sheet` offers any other dismissal
    ///     affordance, so pass `false` only for a hard paywall the user must purchase through.
    ///   - onDismiss: Optional callback fired after the sheet dismisses.
    /// - Returns: A view with the paywall sheet attached.
    public func revenueCatPaywall(
        isPresented: Binding<Bool>,
        displayCloseButton: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            RevenueCatPaywallSheetModifier(
                isPresented: isPresented,
                displayCloseButton: displayCloseButton,
                onDismiss: onDismiss
            )
        )
    }

    /// Attaches the RevenueCat customer center as a platform-appropriate sheet.
    ///
    /// On iOS, presents `RevenueCatUI.CustomerCenterView` in a `sheet`. On macOS, opens
    /// `itms-apps://apps.apple.com/account/subscriptions` in App Store (falling back to the
    /// `https://apps.apple.com/account/subscriptions` web URL if nothing handles the scheme)
    /// and immediately clears the binding (so `isCustomerCenterPresented` does not stick
    /// `true`) before firing `onDismiss`.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatCustomerCenter(
    ///         isPresented: Binding(
    ///             get: { store.paywall.isCustomerCenterPresented },
    ///             set: { if !$0 { store.send(.paywall(.dismissCustomerCenter)) } }
    ///         )
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: Two-way binding to the customer center's visibility flag.
    ///   - onDismiss: Optional callback fired after dismissal (or, on macOS, after the App Store
    ///     URL is opened).
    /// - Returns: A view with the customer-center sheet attached.
    public func revenueCatCustomerCenter(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            RevenueCatCustomerCenterSheetModifier(isPresented: isPresented, onDismiss: onDismiss)
        )
    }

    /// Attaches both the paywall and customer-center sheets driven by `PaywallState`.
    ///
    /// Convenience modifier that composes ``revenueCatPaywall(isPresented:displayCloseButton:onDismiss:)``
    /// and ``revenueCatCustomerCenter(isPresented:onDismiss:)`` in one call. Each sheet's binding
    /// dispatches the matching dismiss action when the system clears it: `.dismiss` for the
    /// paywall, `.dismissCustomerCenter` for the customer center.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
    /// ```
    ///
    /// - Parameters:
    ///   - state: The paywall slice from your store, typically `store.paywall`.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`;
    ///     neither the iOS `fullScreenCover` nor the macOS `sheet` offers any other dismissal
    ///     affordance, so pass `false` only for a hard paywall the user must purchase through.
    ///   - send: A closure that lifts a `PaywallAction` into your root action and dispatches it,
    ///     for example `{ store.send(.paywall($0)) }`.
    /// - Returns: A view with both the paywall and customer-center sheets attached.
    public func revenueCatPaywall(
        state: PaywallState,
        displayCloseButton: Bool = true,
        send: @escaping (PaywallAction) -> Void
    ) -> some View {
        modifier(
            RevenueCatPaywallModifier(
                state: state,
                displayCloseButton: displayCloseButton,
                send: send
            )
        )
    }
}
