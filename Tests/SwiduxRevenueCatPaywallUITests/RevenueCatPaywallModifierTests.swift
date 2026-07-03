//
//  RevenueCatPaywallModifierTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywallUI

@Suite("RevenueCatPaywallModifier")
@MainActor
struct RevenueCatPaywallModifierTests {
    @Test("Modifier does not dispatch on construction")
    func modifierDoesNotDispatchOnConstruction() {
        let recorder = ActionRecorder()
        _ = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )

        #expect(recorder.snapshot.isEmpty)
    }

    @Test("paywallBinding reads state.isPresented")
    func paywallBindingReadsState() {
        let recorder = ActionRecorder()
        let presented = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )
        let hidden = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: false),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )

        #expect(presented.paywallBinding.wrappedValue == true)
        #expect(hidden.paywallBinding.wrappedValue == false)
    }

    @Test("customerCenterBinding reads false while the paywall is presented")
    func customerCenterBindingYieldsToPaywall() {
        let recorder = ActionRecorder()
        let bothRequested = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: true, isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )
        let centerOnly = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: false, isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )

        #expect(
            bothRequested.customerCenterBinding.wrappedValue == false,
            "The paywall wins; the platform must never be asked to present both surfaces."
        )
        #expect(centerOnly.customerCenterBinding.wrappedValue == true)
    }

    @Test("paywallBinding setter dispatches .dismiss only when set to false")
    func paywallBindingSetterDispatchesOnDismissal() {
        let recorder = ActionRecorder()
        let modifier = RevenueCatPaywallModifier(
            state: PaywallState(isPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )

        modifier.paywallBinding.wrappedValue = true
        #expect(recorder.snapshot.isEmpty, "setting to true should not dispatch")

        modifier.paywallBinding.wrappedValue = false
        let actions = recorder.snapshot
        #expect(actions.count == 1)
        if case .dismiss = actions.first {
        } else {
            Issue.record("expected .dismiss, got \(String(describing: actions.first))")
        }
    }

    @Test("customerCenterBinding setter dispatches .dismissCustomerCenter only when set to false")
    func customerCenterBindingSetterDispatchesOnDismissal() {
        let recorder = ActionRecorder()
        let modifier = RevenueCatPaywallModifier(
            state: PaywallState(isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            send: recorder.record
        )

        modifier.customerCenterBinding.wrappedValue = true
        #expect(recorder.snapshot.isEmpty, "setting to true should not dispatch")

        modifier.customerCenterBinding.wrappedValue = false
        let actions = recorder.snapshot
        #expect(actions.count == 1)
        if case .dismissCustomerCenter = actions.first {
        } else {
            Issue.record(
                "expected .dismissCustomerCenter, got \(String(describing: actions.first))"
            )
        }
    }
}

private final class ActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [PaywallAction] = []

    func record(_ action: PaywallAction) {
        lock.withLock { actions.append(action) }
    }

    var snapshot: [PaywallAction] {
        lock.withLock { actions }
    }
}
