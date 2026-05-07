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
                PaywallSheet(isPresented: state.isPresented) {
                    send(.dismiss)
                }
                CustomerCenterSheet(isPresented: state.isCustomerCenterPresented) {
                    send(.dismissCustomerCenter)
                }
            }
    }
}

extension View {
    /// Attaches RevenueCat paywall and customer-center sheets driven by `PaywallState`.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
    /// ```
    public func revenueCatPaywall(
        state: PaywallState,
        send: @escaping (PaywallAction) -> Void
    ) -> some View {
        modifier(RevenueCatPaywallModifier(state: state, send: send))
    }
}
