//
//  ViewSmokeTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import SwiduxPaywall
import SwiftUI
import Testing

@testable import SwiduxRevenueCatPaywallUI

/// Smoke tests that exercise the SwiftUI `body` getters on the bundled views.
///
/// These do not assert on rendered output — that would require a third-party introspection lib.
/// They confirm the views construct cleanly and their bodies evaluate without crashing, which
/// catches construction-time regressions in the platform-conditional presentation code.
@Suite("View smoke tests")
@MainActor
struct ViewSmokeTests {
    @Test("PaywallSheet body evaluates when not presented")
    func paywallSheetBodyEvaluatesNotPresented() {
        let sheet = PaywallSheet(isPresented: false, onDismiss: {})
        _ = sheet.body
    }

    @Test("PaywallSheet body evaluates when presented")
    func paywallSheetBodyEvaluatesPresented() {
        let sheet = PaywallSheet(isPresented: true, onDismiss: {})
        _ = sheet.body
    }

    @Test("CustomerCenterSheet body evaluates when not presented")
    func customerCenterSheetBodyEvaluatesNotPresented() {
        let sheet = CustomerCenterSheet(isPresented: false, onDismiss: {})
        _ = sheet.body
    }

    @Test("CustomerCenterSheet body evaluates when presented")
    func customerCenterSheetBodyEvaluatesPresented() {
        let sheet = CustomerCenterSheet(isPresented: true, onDismiss: {})
        _ = sheet.body
    }

    @Test("revenueCatPaywall modifier composes onto a view")
    func revenueCatPaywallModifierComposes() {
        // Constructing the modified view is sufficient smoke. SwiftUI's `ModifiedContent.body`
        // traps when accessed outside a render pass, so we don't try to evaluate it here.
        _ = EmptyView().revenueCatPaywall(state: PaywallState()) { _ in }
    }
}
