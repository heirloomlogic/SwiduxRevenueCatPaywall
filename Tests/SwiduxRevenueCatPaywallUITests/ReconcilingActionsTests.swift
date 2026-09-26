//
//  ReconcilingActionsTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywallUI

/// Collapses `PaywallAction` (not `Equatable`) to the cases reconciliation can produce.
private enum Reconciled: Equatable {
    case dismiss
    case dismissCustomerCenter
    case other
}

private func reconciled(from old: PaywallState, to new: PaywallState) -> [Reconciled] {
    RevenueCatPaywallModifier.reconcilingActions(from: old, to: new).map {
        switch $0 {
        case .dismiss: .dismiss
        case .dismissCustomerCenter: .dismissCustomerCenter
        default: .other
        }
    }
}

@Suite("RevenueCatPaywallModifier.reconcilingActions")
@MainActor
struct ReconcilingActionsTests {
    @Test("Becoming entitled while the paywall is up dismisses it (restore path)")
    func entitlementWhilePresentedDismisses() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(isPro: true, isPresented: true)
        )
        #expect(actions == [.dismiss])
    }

    @Test("A permanent license also satisfies the gate and dismisses")
    func permanentLicenseDismisses() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(hasPermanentLicense: true, isPresented: true)
        )
        #expect(actions == [.dismiss])
    }

    @Test("An already-entitled user can keep the paywall open")
    func alreadyEntitledStaysOpen() {
        let actions = reconciled(
            from: PaywallState(isPro: true),
            to: PaywallState(isPro: true, isPresented: true)
        )
        #expect(actions.isEmpty)
    }

    @Test("Becoming entitled with no paywall up dispatches nothing")
    func entitlementWithoutPaywallIsQuiet() {
        let actions = reconciled(from: PaywallState(), to: PaywallState(isPro: true))
        #expect(actions.isEmpty)
    }

    @Test("A paywall request while the customer center is up dismisses the customer center")
    func paywallRequestYieldsCustomerCenter() {
        let actions = reconciled(
            from: PaywallState(isCustomerCenterPresented: true),
            to: PaywallState(isPresented: true, isCustomerCenterPresented: true)
        )
        #expect(actions == [.dismissCustomerCenter])
    }

    @Test("A customer-center request while the paywall is up is refused")
    func customerCenterRequestRefused() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(isPresented: true, isCustomerCenterPresented: true)
        )
        #expect(actions == [.dismissCustomerCenter])
    }

    @Test("An unrelated change while both flags stay set does not re-dispatch")
    func unrelatedChangeDoesNotRedispatch() {
        let actions = reconciled(
            from: PaywallState(isPresented: true, isCustomerCenterPresented: true),
            to: PaywallState(isPresented: true, isLoading: true, isCustomerCenterPresented: true)
        )
        #expect(actions.isEmpty)
    }
}
