//
//  ObserverModeHandlersTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import RevenueCat
import StoreKit
import Testing

@testable import SwiduxRevenueCatPaywallUI

@Suite("Observer-mode paywall handlers")
@MainActor
struct ObserverModeHandlersTests {
    @Test("RevenueCat completion mode leaves purchase handling to RevenueCatUI")
    func revenueCatModeUsesSDKHandlers() {
        let handlers = ObserverModePaywallAdapter.handlers(for: .revenueCat, purchaseLogic: nil)

        #expect(handlers.purchase == nil)
        #expect(handlers.restore == nil)
    }

    @Test("Observer mode always supplies both handlers")
    func observerModeAlwaysSuppliesHandlers() {
        let handlers = ObserverModePaywallAdapter.handlers(for: .myApp, purchaseLogic: nil)

        #expect(handlers.purchase != nil)
        #expect(handlers.restore != nil)
    }

    @Test("Missing purchase logic reports a configuration error without trapping")
    func missingPurchaseLogicReturnsError() async {
        let result = await ObserverModePaywallAdapter.purchase(
            product: nil,
            purchaseLogic: nil,
            recordPurchase: { _ in Issue.record("recordPurchase must not run") }
        )

        #expect(!result.userCancelled)
        #expect(result.error is ObserverModePaywallError)
    }

    @Test("A cancelled StoreKit purchase is reported before cancellation is returned")
    func cancelledPurchaseIsReported() async {
        let events = EventRecorder()
        let result = await ObserverModePaywallAdapter.completePurchase(
            .userCancelled,
            recordPurchase: { purchaseResult in
                events.append(purchaseResult.isUserCancelled ? "record-cancelled" : "record-other")
            }
        )
        events.append("return")

        #expect(events.snapshot == ["record-cancelled", "return"])
        #expect(result.userCancelled)
        #expect(result.error == nil)
    }

    @Test("A pending StoreKit purchase is reported and is not treated as cancellation")
    func pendingPurchaseIsReported() async {
        let events = EventRecorder()
        let result = await ObserverModePaywallAdapter.completePurchase(
            .pending,
            recordPurchase: { purchaseResult in
                events.append(purchaseResult.isPending ? "record-pending" : "record-other")
            }
        )

        #expect(events.snapshot == ["record-pending"])
        #expect(!result.userCancelled)
        #expect(result.error is ObserverModePaywallError)
    }

    @Test("A reporting error is returned to RevenueCatUI")
    func reportingErrorIsReturned() async {
        let result = await ObserverModePaywallAdapter.completePurchase(
            .pending,
            recordPurchase: { _ in throw TestError.expected }
        )

        #expect(!result.userCancelled)
        #expect(result.error is TestError)
    }

    @Test("Restore runs app logic before RevenueCat synchronization")
    func restoreRunsInOrder() async {
        let events = EventRecorder()
        let result = await ObserverModePaywallAdapter.restore(
            purchaseLogic: RevenueCatPaywallPurchaseLogic(
                purchase: { _ in .pending },
                restore: { events.append("app-restore") }
            ),
            syncPurchases: {
                events.append("revenuecat-sync")
                return true
            }
        )

        #expect(events.snapshot == ["app-restore", "revenuecat-sync"])
        #expect(result.success)
        #expect(result.error == nil)
    }

    @Test("A restore error prevents RevenueCat synchronization")
    func restoreFailureStopsBeforeSync() async {
        let events = EventRecorder()
        let result = await ObserverModePaywallAdapter.restore(
            purchaseLogic: RevenueCatPaywallPurchaseLogic(
                purchase: { _ in .pending },
                restore: { throw TestError.expected }
            ),
            syncPurchases: {
                events.append("revenuecat-sync")
                return true
            }
        )

        #expect(events.snapshot.isEmpty)
        #expect(!result.success)
        #expect(result.error is TestError)
    }
}

private enum TestError: Error {
    case expected
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock { events.append(event) }
    }

    var snapshot: [String] {
        lock.withLock { events }
    }
}

extension Product.PurchaseResult {
    fileprivate var isPending: Bool {
        if case .pending = self { true } else { false }
    }

    fileprivate var isUserCancelled: Bool {
        if case .userCancelled = self { true } else { false }
    }
}
