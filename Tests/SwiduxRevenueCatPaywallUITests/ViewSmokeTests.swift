//
//  ViewSmokeTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import SwiduxPaywall
import SwiftUI
import Testing

@testable import SwiduxRevenueCatPaywallUI

/// Smoke tests that exercise composition of the bundled view modifiers.
///
/// `ModifiedContent.body` traps when accessed outside a render pass, so these tests confirm only
/// that the modifier chain composes onto a `View` without crashing at construction. Rendered
/// behavior is covered indirectly by `RevenueCatPaywallModifierTests`, which exercises the
/// dispatch path through the modifier's bindings.
@Suite("View smoke tests")
@MainActor
struct ViewSmokeTests {
    @Test("revenueCatPaywall(isPresented:onDismiss:) composes onto a view")
    func revenueCatPaywallPrimitiveComposes() {
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 })
        )
    }

    @Test("revenueCatCustomerCenter(isPresented:onDismiss:) composes onto a view")
    func revenueCatCustomerCenterPrimitiveComposes() {
        var flag = false
        _ = EmptyView().revenueCatCustomerCenter(
            isPresented: Binding(get: { flag }, set: { flag = $0 })
        )
    }

    @Test("revenueCatPaywall(state:send:) composes onto a view")
    func revenueCatPaywallConvenienceComposes() {
        _ = EmptyView().revenueCatPaywall(state: PaywallState()) { _ in }
    }

    @Test("revenueCatPaywall accepts displayCloseButton on both overloads")
    func revenueCatPaywallDisplayCloseButtonComposes() {
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            displayCloseButton: false
        )
        _ = EmptyView().revenueCatPaywall(state: PaywallState(), displayCloseButton: false) { _ in }
    }
}
