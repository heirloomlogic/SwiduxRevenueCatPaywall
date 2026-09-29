//
//  HostedPresentationTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import SwiduxPaywall
import SwiftUI
import Testing

@testable import SwiduxRevenueCatPaywallUI

#if os(macOS)
import AppKit

@Suite("Hosted macOS presentation", .serialized)
@MainActor
struct HostedMacPresentationTests {
    @Test("An initial customer-center request opens through Swidux and clears once")
    func initialCustomerCenterRequestOpensThenClears() async throws {
        let recorder = HostedActionRecorder()
        let rootView = Color.clear
            .frame(width: 320, height: 240)
            .revenueCatPaywall(
                state: PaywallState(isPresented: true, isCustomerCenterPresented: true),
                send: recorder.record
            )
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        defer { window.close() }

        try await waitUntil { recorder.events.count == 2 && window.attachedSheet != nil }

        #expect(recorder.events == [.openManageSubscriptions, .dismissCustomerCenter])
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.events == [.openManageSubscriptions, .dismissCustomerCenter])
    }
}
#elseif os(iOS)
import SwiduxRevenueCatPaywall
import UIKit

@Suite("Hosted iOS presentation", .serialized)
@MainActor
struct HostedIOSPresentationTests {
    @Test("An initial two-flag state presents only the paywall")
    func initialTwoFlagStateKeepsPaywallExclusive() async throws {
        RevenueCatPaywall.configure(
            apiKey: "appl_test_api_key",
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: .storeKit2
        )
        let recorder = HostedActionRecorder()
        let controller = UIHostingController(
            rootView: Color.clear
                .revenueCatPaywall(
                    state: PaywallState(isPresented: true, isCustomerCenterPresented: true),
                    send: recorder.record
                )
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await waitUntil {
            controller.presentedViewController != nil && recorder.events == [.dismissCustomerCenter]
        }

        #expect(controller.presentedViewController?.modalPresentationStyle == .overFullScreen)
        #expect(recorder.events == [.dismissCustomerCenter])
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.events == [.dismissCustomerCenter])
    }

    @Test("A hard paywall sheet disables interactive dismissal")
    func hardPaywallSheetDisablesInteractiveDismissal() async throws {
        RevenueCatPaywall.configure(
            apiKey: "appl_test_api_key",
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: .storeKit2
        )
        let controller = UIHostingController(
            rootView: Color.clear.revenueCatPaywall(
                isPresented: .constant(true),
                displayCloseButton: false,
                presentationStyle: .sheet
            )
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await waitUntil { controller.presentedViewController != nil }

        #expect(controller.presentedViewController?.isModalInPresentation == true)
    }
}
#endif

private enum HostedAction: Equatable {
    case openManageSubscriptions
    case dismissCustomerCenter
    case other
}

@MainActor
private final class HostedActionRecorder {
    private(set) var events: [HostedAction] = []

    func record(_ action: PaywallAction) {
        switch action {
        case .openManageSubscriptions:
            events.append(.openManageSubscriptions)
        case .dismissCustomerCenter:
            events.append(.dismissCustomerCenter)
        default:
            events.append(.other)
        }
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(condition(), "Timed out waiting for hosted presentation")
}
