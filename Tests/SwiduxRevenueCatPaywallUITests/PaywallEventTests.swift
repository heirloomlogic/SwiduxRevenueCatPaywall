//
//  PaywallEventTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import RevenueCat
import Testing

@testable import SwiduxRevenueCatPaywallUI

@Suite("RevenueCatPaywallEvent mapping")
@MainActor
struct PaywallEventTests {
    @Test("Purchase completion keeps Foundation transaction and customer identifiers")
    func purchaseCompletionMapsIdentifiers() {
        let transaction = StoreTransaction(
            productIdentifier: "pro.monthly",
            purchaseDate: Date(timeIntervalSince1970: 100),
            transactionIdentifier: "transaction-42"
        )
        let info = makeEventCustomerInfo(
            activeSubscriptions: ["pro.monthly"],
            purchasedProducts: ["pro.monthly", "lifetime"]
        )

        let event = RevenueCatPaywallEvent.purchaseCompleted(
            transaction: transaction,
            customerInfo: info
        )

        #expect(
            event
                == .purchaseCompleted(
                    RevenueCatPaywallPurchaseResult(
                        productIdentifier: "pro.monthly",
                        transactionIdentifier: "transaction-42",
                        activeSubscriptionProductIdentifiers: ["pro.monthly"],
                        purchasedProductIdentifiers: ["pro.monthly", "lifetime"]
                    )
                )
        )
    }

    @Test("Purchase completion represents web checkout without a StoreKit transaction")
    func purchaseCompletionAllowsMissingTransaction() {
        let event = RevenueCatPaywallEvent.purchaseCompleted(
            transaction: nil,
            customerInfo: makeEventCustomerInfo(activeSubscriptions: [], purchasedProducts: [])
        )

        #expect(
            event
                == .purchaseCompleted(
                    RevenueCatPaywallPurchaseResult(
                        productIdentifier: nil,
                        transactionIdentifier: nil,
                        activeSubscriptionProductIdentifiers: [],
                        purchasedProductIdentifiers: []
                    )
                )
        )
    }

    @Test("Restore completion keeps the restored product identifiers")
    func restoreCompletionMapsIdentifiers() {
        let event = RevenueCatPaywallEvent.restoreCompleted(
            customerInfo: makeEventCustomerInfo(
                activeSubscriptions: ["pro.annual"],
                purchasedProducts: ["pro.annual"]
            )
        )

        #expect(
            event
                == .restoreCompleted(
                    RevenueCatPaywallRestoreResult(
                        activeSubscriptionProductIdentifiers: ["pro.annual"],
                        purchasedProductIdentifiers: ["pro.annual"]
                    )
                )
        )
    }

    @Test("Failures keep stable NSError fields without exposing an SDK error type")
    func failureMapsNSErrorFields() {
        let error = NSError(domain: "StoreKitError", code: 19, userInfo: [NSLocalizedDescriptionKey: "Payment failed"])

        #expect(
            RevenueCatPaywallEvent.purchaseFailed(error)
                == .purchaseFailed(
                    RevenueCatPaywallFailure(domain: "StoreKitError", code: 19, message: "Payment failed"))
        )
        #expect(
            RevenueCatPaywallEvent.restoreFailed(error)
                == .restoreFailed(
                    RevenueCatPaywallFailure(domain: "StoreKitError", code: 19, message: "Payment failed"))
        )
    }
}

private func makeEventCustomerInfo(
    activeSubscriptions: Set<String>,
    purchasedProducts: Set<String>
) -> CustomerInfo {
    let now = Date()
    return CustomerInfo(
        entitlements: EntitlementInfos(entitlements: [:], verification: .notRequested),
        expirationDatesByProductId: Dictionary(
            uniqueKeysWithValues: activeSubscriptions.map { ($0, now.addingTimeInterval(3_600)) }),
        allPurchasedProductIds: purchasedProducts,
        requestDate: now,
        firstSeen: now,
        originalAppUserId: "test-user"
    )
}
