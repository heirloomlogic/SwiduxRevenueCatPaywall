//
//  RevenueCatPaywallModifierTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywallUI

@Suite("RevenueCatPaywallModifier")
struct RevenueCatPaywallModifierTests {
    @Test("dismissPaywall dispatches PaywallAction.dismiss")
    func dismissPaywallDispatchesDismiss() {
        let recorder = ActionRecorder()
        let modifier = RevenueCatPaywallModifier(state: PaywallState(), send: recorder.record)

        modifier.dismissPaywall()

        let actions = recorder.snapshot
        #expect(actions.count == 1)
        if case .dismiss = actions.first {
        } else {
            Issue.record("expected .dismiss, got \(String(describing: actions.first))")
        }
    }

    @Test("dismissCustomerCenter dispatches PaywallAction.dismissCustomerCenter")
    func dismissCustomerCenterDispatchesAction() {
        let recorder = ActionRecorder()
        let modifier = RevenueCatPaywallModifier(state: PaywallState(), send: recorder.record)

        modifier.dismissCustomerCenter()

        let actions = recorder.snapshot
        #expect(actions.count == 1)
        if case .dismissCustomerCenter = actions.first {
        } else {
            Issue.record("expected .dismissCustomerCenter, got \(String(describing: actions.first))")
        }
    }

    @Test("Modifier does not dispatch on construction")
    func modifierDoesNotDispatchOnConstruction() {
        let recorder = ActionRecorder()
        _ = RevenueCatPaywallModifier(state: PaywallState(isPresented: true), send: recorder.record)

        #expect(recorder.snapshot.isEmpty)
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
