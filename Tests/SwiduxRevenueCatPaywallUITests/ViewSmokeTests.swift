//
//  ViewSmokeTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import RevenueCat
import RevenueCatUI
import SwiduxPaywall
import SwiduxRevenueCatPaywall
import SwiftUI
import Testing

@testable import SwiduxRevenueCatPaywallUI

#if os(iOS)
import UIKit
#endif

/// Smoke tests that exercise composition of the bundled view modifiers.
///
/// Most tests confirm that the modifier chain composes onto a `View` without crashing at construction. The iOS observer-mode test also mounts the public modifier in a window and presents its full-screen cover.
@Suite("View smoke tests", .serialized)
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

    @Test("revenueCatPaywallAndCustomerCenter(state:onAction:) composes onto a view")
    func revenueCatPaywallAndCustomerCenterComposes() {
        _ = EmptyView().revenueCatPaywallAndCustomerCenter(state: PaywallState(), onAction: { _ in })
    }

    @Test("The paywall APIs accept displayCloseButton")
    func paywallAPIsAcceptDisplayCloseButton() {
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            displayCloseButton: false
        )
        _ = EmptyView().revenueCatPaywallAndCustomerCenter(
            state: PaywallState(),
            displayCloseButton: false,
            onAction: { _ in }
        )
    }

    @Test("The paywall APIs accept offeringIdentifier")
    func paywallAPIsAcceptOfferingIdentifier() {
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            offeringIdentifier: "winback"
        )
        _ = EmptyView().revenueCatPaywallAndCustomerCenter(
            state: PaywallState(),
            offeringIdentifier: "winback",
            onAction: { _ in }
        )
    }

    @Test("The paywall APIs accept observer-mode purchase logic")
    func paywallAPIsAcceptObserverModeLogic() {
        let logic = RevenueCatPaywallPurchaseLogic(
            purchase: { _ in .pending },
            restore: {}
        )
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            purchaseLogic: logic
        )
        _ = EmptyView().revenueCatPaywallAndCustomerCenter(
            state: PaywallState(),
            purchaseLogic: logic,
            onAction: { _ in }
        )
    }

    @Test("The paywall APIs accept outcome, font, and presentation options")
    func paywallAPIsAcceptOptions() {
        let fonts = DefaultPaywallFontProvider()
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            fonts: fonts,
            presentationStyle: .sheet,
            onEvent: { _ in }
        )
        _ = EmptyView().revenueCatPaywallAndCustomerCenter(
            state: PaywallState(),
            fonts: fonts,
            presentationStyle: .automatic,
            onEvent: { _ in },
            onAction: { _ in }
        )
    }

    #if os(macOS)
    @Test("Escape dismisses only when the close button is available")
    func escapeRespectsHardPaywall() {
        var dismissals = 0
        ResolvedOfferingPaywallView.handleExitCommand(
            displayCloseButton: true,
            onRequestDismiss: { dismissals += 1 }
        )
        ResolvedOfferingPaywallView.handleExitCommand(
            displayCloseButton: false,
            onRequestDismiss: { dismissals += 1 }
        )

        #expect(dismissals == 1)
    }
    #endif

    #if os(iOS)
    @Test("Observer-mode paywall presents in a hosted hierarchy")
    func observerModePaywallPresents() async throws {
        RevenueCatPaywall.configure(
            apiKey: "appl_test_api_key",
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: .storeKit2
        )
        #expect(Purchases.shared.purchasesAreCompletedBy == .myApp)

        let controller = UIHostingController(rootView: ObserverModePaywallHost())
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<40 where controller.presentedViewController == nil {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(controller.presentedViewController != nil)
    }
    #endif
}

#if os(iOS)
private struct ObserverModePaywallHost: View {
    @State private var isPresented = true

    var body: some View {
        EmptyView().revenueCatPaywall(isPresented: $isPresented)
    }
}
#endif
