//
//  PaywallViewModifier.swift
//  SwiduxRevenueCatPaywallUI
//

import SwiduxPaywall
import SwiftUI

/// Composes paywall and customer-center sheets onto a view, driven by `PaywallState`.
struct RevenueCatPaywallModifier: ViewModifier {
    let state: PaywallState
    let send: (PaywallAction) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                PaywallSheet(isPresented: state.isPresented, onDismiss: dismissPaywall)
                CustomerCenterSheet(
                    isPresented: state.isCustomerCenterPresented,
                    onDismiss: dismissCustomerCenter
                )
            }
    }

    func dismissPaywall() { send(.dismiss) }

    func dismissCustomerCenter() { send(.dismissCustomerCenter) }
}

extension View {
    /// Attaches both ``PaywallSheet`` and ``CustomerCenterSheet`` driven by `PaywallState`.
    ///
    /// Convenience modifier that composes both sheets in one call and dispatches the matching
    /// dismiss action when each closes (`.dismiss` for the paywall, `.dismissCustomerCenter`
    /// for the customer center).
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
    /// ```
    ///
    /// Equivalent to attaching both sheets manually:
    ///
    /// ```swift
    /// ContentView()
    ///     .background(
    ///         PaywallSheet(
    ///             isPresented: store.paywall.isPresented,
    ///             onDismiss: { store.send(.paywall(.dismiss)) }
    ///         )
    ///     )
    ///     .background(
    ///         CustomerCenterSheet(
    ///             isPresented: store.paywall.isCustomerCenterPresented,
    ///             onDismiss: { store.send(.paywall(.dismissCustomerCenter)) }
    ///         )
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - state: The paywall slice from your store, typically `store.paywall`.
    ///   - send: A closure that lifts a `PaywallAction` into your root action and dispatches it,
    ///     for example `{ store.send(.paywall($0)) }`.
    /// - Returns: A view with both `PaywallSheet` and `CustomerCenterSheet` attached, ready to
    ///   present whichever the paywall plugin signals.
    public func revenueCatPaywall(
        state: PaywallState,
        send: @escaping (PaywallAction) -> Void
    ) -> some View {
        modifier(RevenueCatPaywallModifier(state: state, send: send))
    }
}
