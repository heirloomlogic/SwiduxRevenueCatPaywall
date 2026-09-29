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

    @Test("revenueCatPaywall accepts offeringIdentifier on both overloads")
    func revenueCatPaywallOfferingIdentifierComposes() {
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            offeringIdentifier: "winback"
        )
        _ = EmptyView().revenueCatPaywall(
            state: PaywallState(),
            offeringIdentifier: "winback"
        ) { _ in }
    }

    @Test("revenueCatPaywall accepts observer-mode purchase logic on both overloads")
    func revenueCatPaywallObserverModeLogicComposes() {
        let logic = RevenueCatPaywallPurchaseLogic(
            purchase: { _ in .pending },
            restore: {}
        )
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            purchaseLogic: logic
        )
        _ = EmptyView().revenueCatPaywall(
            state: PaywallState(),
            purchaseLogic: logic
        ) { _ in }
    }

    @Test("revenueCatPaywall accepts outcome, font, and presentation options on both overloads")
    func revenueCatPaywallOptionsCompose() {
        let fonts = DefaultPaywallFontProvider()
        var flag = false
        _ = EmptyView().revenueCatPaywall(
            isPresented: Binding(get: { flag }, set: { flag = $0 }),
            fonts: fonts,
            presentationStyle: .sheet,
            onEvent: { _ in }
        )
        _ = EmptyView().revenueCatPaywall(
            state: PaywallState(),
            fonts: fonts,
            presentationStyle: .automatic,
            onEvent: { _ in },
            send: { _ in }
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
