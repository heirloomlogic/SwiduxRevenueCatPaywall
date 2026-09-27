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

@MainActor
private func reconciled(
    from old: PaywallState,
    to new: PaywallState,
    restoreCompleted: Bool = false
) -> [Reconciled] {
    RevenueCatPaywallModifier.reconcilingActions(from: old, to: new, restoreCompleted: restoreCompleted).map {
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
    @Test("Entitlement arriving after a completed restore dismisses the paywall")
    func entitlementAfterRestoreDismisses() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(isPro: true, isPresented: true),
            restoreCompleted: true
        )
        #expect(actions == [.dismiss])
    }

    @Test("A restored permanent license also dismisses")
    func restoredPermanentLicenseDismisses() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(hasPermanentLicense: true, isPresented: true),
            restoreCompleted: true
        )
        #expect(actions == [.dismiss])
    }

    @Test("Entitlement arriving without a restore leaves the paywall to RevenueCatUI")
    func entitlementWithoutRestoreIsQuiet() {
        // A purchase: RevenueCatUI dismisses on its own. A launch read or cache seed landing
        // while an entitled user browses the paywall must not close it on them.
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(isPro: true, isPresented: true)
        )
        #expect(actions.isEmpty)
    }

    @Test("Becoming entitled with no paywall up dispatches nothing")
    func entitlementWithoutPaywallIsQuiet() {
        let actions = reconciled(from: PaywallState(), to: PaywallState(isPro: true), restoreCompleted: true)
        #expect(actions.isEmpty)
    }

    #if os(iOS)
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
    #else
    @Test("A paywall request does not discard a macOS subscription-management request")
    func paywallRequestPreservesSubscriptionManagement() {
        let actions = reconciled(
            from: PaywallState(isCustomerCenterPresented: true),
            to: PaywallState(isPresented: true, isCustomerCenterPresented: true)
        )
        #expect(actions.isEmpty)
    }

    @Test("A macOS subscription-management request is not refused while the paywall is up")
    func subscriptionManagementRequestIsPreserved() {
        let actions = reconciled(
            from: PaywallState(isPresented: true),
            to: PaywallState(isPresented: true, isCustomerCenterPresented: true)
        )
        #expect(actions.isEmpty)
    }
    #endif
}

@Suite("RevenueCatPaywallModifier.closesAfterRestore")
@MainActor
struct ClosesAfterRestoreTests {
    @Test("A restore that leaves the user entitled closes the presented paywall")
    func entitledRestoreCloses() {
        #expect(RevenueCatPaywallModifier.closesAfterRestore(PaywallState(isPro: true, isPresented: true)))
        #expect(
            RevenueCatPaywallModifier.closesAfterRestore(PaywallState(hasPermanentLicense: true, isPresented: true))
        )
    }

    @Test("A restore that found nothing keeps the paywall up")
    func emptyRestoreStays() {
        #expect(!RevenueCatPaywallModifier.closesAfterRestore(PaywallState(isPresented: true)))
    }

    @Test("Nothing to close when the paywall isn't presented")
    func notPresentedIsQuiet() {
        #expect(!RevenueCatPaywallModifier.closesAfterRestore(PaywallState(isPro: true)))
    }
}
