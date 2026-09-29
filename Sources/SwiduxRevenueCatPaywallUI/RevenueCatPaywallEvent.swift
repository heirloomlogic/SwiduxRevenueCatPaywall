//
//  RevenueCatPaywallEvent.swift
//  SwiduxRevenueCatPaywallUI
//

import Foundation
import RevenueCat

/// A purchase, restore, cancellation, or failure reported by the bundled paywall.
public enum RevenueCatPaywallEvent: Sendable, Equatable {
    /// A purchase completed, including StoreKit identifiers when RevenueCat supplied a transaction.
    case purchaseCompleted(RevenueCatPaywallPurchaseResult)
    /// The customer cancelled a purchase.
    case purchaseCancelled
    /// A purchase failed.
    case purchaseFailed(RevenueCatPaywallFailure)
    /// A restore completed. A successful restore can still contain no active subscriptions.
    case restoreCompleted(RevenueCatPaywallRestoreResult)
    /// A restore failed.
    case restoreFailed(RevenueCatPaywallFailure)
}

/// Foundation values reported after a completed paywall purchase.
public struct RevenueCatPaywallPurchaseResult: Sendable, Equatable {
    /// StoreKit product identifier, or `nil` when the purchase completed outside StoreKit.
    public let productIdentifier: String?
    /// StoreKit transaction identifier, or `nil` when RevenueCat did not supply a transaction.
    public let transactionIdentifier: String?
    /// Subscription product identifiers active in RevenueCat's returned customer information.
    public let activeSubscriptionProductIdentifiers: Set<String>
    /// All product identifiers present in RevenueCat's returned customer information.
    public let purchasedProductIdentifiers: Set<String>

    /// Creates a purchase result.
    public init(
        productIdentifier: String?,
        transactionIdentifier: String?,
        activeSubscriptionProductIdentifiers: Set<String>,
        purchasedProductIdentifiers: Set<String>
    ) {
        self.productIdentifier = productIdentifier
        self.transactionIdentifier = transactionIdentifier
        self.activeSubscriptionProductIdentifiers = activeSubscriptionProductIdentifiers
        self.purchasedProductIdentifiers = purchasedProductIdentifiers
    }
}

/// Foundation values reported after a completed restore.
public struct RevenueCatPaywallRestoreResult: Sendable, Equatable {
    /// Subscription product identifiers active in RevenueCat's returned customer information.
    public let activeSubscriptionProductIdentifiers: Set<String>
    /// All product identifiers present in RevenueCat's returned customer information.
    public let purchasedProductIdentifiers: Set<String>

    /// Creates a restore result.
    public init(
        activeSubscriptionProductIdentifiers: Set<String>,
        purchasedProductIdentifiers: Set<String>
    ) {
        self.activeSubscriptionProductIdentifiers = activeSubscriptionProductIdentifiers
        self.purchasedProductIdentifiers = purchasedProductIdentifiers
    }
}

/// Stable error fields reported by a failed paywall purchase or restore.
public struct RevenueCatPaywallFailure: Error, Sendable, Equatable {
    /// The error domain.
    public let domain: String
    /// The error code.
    public let code: Int
    /// The localized error description available when the failure occurred.
    public let message: String

    /// Creates a failure value.
    public init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }
}

/// Receives events generated inside the package-owned presentation boundary.
public typealias RevenueCatPaywallEventHandler = @MainActor @Sendable (RevenueCatPaywallEvent) -> Void

extension RevenueCatPaywallEvent {
    static func purchaseCompleted(
        transaction: StoreTransaction?,
        customerInfo: CustomerInfo
    ) -> Self {
        .purchaseCompleted(
            RevenueCatPaywallPurchaseResult(
                productIdentifier: transaction?.productIdentifier,
                transactionIdentifier: transaction?.transactionIdentifier,
                activeSubscriptionProductIdentifiers: customerInfo.activeSubscriptions,
                purchasedProductIdentifiers: customerInfo.allPurchasedProductIdentifiers
            )
        )
    }

    static func restoreCompleted(customerInfo: CustomerInfo) -> Self {
        .restoreCompleted(
            RevenueCatPaywallRestoreResult(
                activeSubscriptionProductIdentifiers: customerInfo.activeSubscriptions,
                purchasedProductIdentifiers: customerInfo.allPurchasedProductIdentifiers
            )
        )
    }

    static func purchaseFailed(_ error: NSError) -> Self {
        .purchaseFailed(RevenueCatPaywallFailure(error))
    }

    static func restoreFailed(_ error: NSError) -> Self {
        .restoreFailed(RevenueCatPaywallFailure(error))
    }
}

extension RevenueCatPaywallFailure {
    fileprivate init(_ error: NSError) {
        self.init(domain: error.domain, code: error.code, message: error.localizedDescription)
    }
}
