//
//  RevenueCatPaywallModifierTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywallUI

@Suite("RevenueCatPaywallAndCustomerCenterModifier")
@MainActor
struct RevenueCatPaywallAndCustomerCenterModifierTests {
    @Test("paywallBinding reads state.isPresented")
    func paywallBindingReadsState() {
        let recorder = ActionRecorder()
        let presented = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
        )
        let hidden = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: false),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
        )

        #expect(presented.paywallBinding.wrappedValue == true)
        #expect(hidden.paywallBinding.wrappedValue == false)
    }

    @Test("customerCenterBinding applies the platform presentation policy")
    func customerCenterBindingUsesPlatformPolicy() {
        let recorder = ActionRecorder()
        let bothRequested = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: true, isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
        )
        let centerOnly = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: false, isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
        )

        #if os(iOS)
        #expect(!bothRequested.customerCenterBinding.wrappedValue)
        #else
        #expect(bothRequested.customerCenterBinding.wrappedValue)
        #endif
        #expect(centerOnly.customerCenterBinding.wrappedValue == true)
    }

    @Test("paywallBinding setter dispatches .dismiss only when set to false")
    func paywallBindingSetterDispatchesOnDismissal() {
        let recorder = ActionRecorder()
        let modifier = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
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
        let modifier = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isCustomerCenterPresented: true),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: recorder.record
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

    @Test("The state modifier forwards requestedReason as a placement")
    func requestedReasonBecomesPlacement() {
        let modifier = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: true, requestedReason: "export"),
            offeringIdentifier: nil,
            displayCloseButton: true,
            onAction: { _ in }
        )

        #expect(modifier.placementIdentifier == "export")
    }

    @Test("An explicit offering identifier takes precedence over requestedReason")
    func explicitOfferingTakesPrecedence() {
        let modifier = RevenueCatPaywallAndCustomerCenterModifier(
            state: PaywallState(isPresented: true, requestedReason: "export"),
            offeringIdentifier: "winback",
            displayCloseButton: true,
            onAction: { _ in }
        )

        #expect(modifier.placementIdentifier == nil)
    }

    @Test("Automatic presentation uses the platform default")
    func automaticPresentationUsesPlatformDefault() {
        #if os(iOS)
        #expect(RevenueCatPaywallPresentationStyle.automatic.resolved(horizontalSizeClass: .compact) == .fullScreen)
        #expect(RevenueCatPaywallPresentationStyle.automatic.resolved(horizontalSizeClass: .regular) == .sheet)
        #else
        #expect(RevenueCatPaywallPresentationStyle.automatic.resolved() == .sheet)
        #endif
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
