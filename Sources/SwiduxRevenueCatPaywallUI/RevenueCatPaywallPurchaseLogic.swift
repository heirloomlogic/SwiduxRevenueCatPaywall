//
//  RevenueCatPaywallPurchaseLogic.swift
//  SwiduxRevenueCatPaywallUI
//

import Foundation
import RevenueCat
import RevenueCatUI
import StoreKit
import SwiduxRevenueCatPaywall

/// App-owned StoreKit 2 operations used by the bundled paywall in observer mode.
///
/// Configure RevenueCat with `purchasesAreCompletedBy: .myApp` and `storeKitVersion: .storeKit2`, then pass one value to either paywall-presenting modifier. The purchase closure calls `Product.purchase()` and returns its result unchanged. The package reports that result to RevenueCat, then finishes a verified transaction. The restore closure refreshes StoreKit's transaction state, normally by calling `AppStore.sync()`; the package synchronizes RevenueCat after it returns.
public struct RevenueCatPaywallPurchaseLogic: Sendable {
    /// App-owned StoreKit 2 purchase operation.
    public typealias Purchase = @MainActor @Sendable (Product) async throws -> Product.PurchaseResult

    /// App-owned StoreKit restore operation, normally `AppStore.sync()`.
    public typealias Restore = @MainActor @Sendable () async throws -> Void

    let purchase: Purchase
    let restore: Restore

    /// Creates the StoreKit 2 operations used by the bundled paywall in observer mode.
    public init(purchase: @escaping Purchase, restore: @escaping Restore) {
        self.purchase = purchase
        self.restore = restore
    }
}

enum ObserverModePaywallError: LocalizedError {
    case purchaseLogicRequired
    case storeKit2ProductUnavailable(String)
    case purchasePending

    var errorDescription: String? {
        switch self {
        case .purchaseLogicRequired:
            "Observer mode requires purchaseLogic on the revenueCatPaywall modifier."
        case .storeKit2ProductUnavailable(let identifier):
            "The RevenueCat package for \(identifier) does not contain a StoreKit 2 product."
        case .purchasePending:
            "The purchase is pending approval. Access will update after StoreKit completes it."
        }
    }
}

struct ObserverModePaywallHandlers {
    let purchase: PerformPurchase?
    let restore: PerformRestore?
}

@MainActor
enum ObserverModePaywallAdapter {
    typealias RecordPurchase = @MainActor @Sendable (Product.PurchaseResult) async throws -> Void
    typealias SyncPurchases = @MainActor @Sendable () async throws -> Bool

    static func handlers(
        for completedBy: PurchasesAreCompletedBy,
        purchaseLogic: RevenueCatPaywallPurchaseLogic?
    ) -> ObserverModePaywallHandlers {
        guard completedBy == .myApp else {
            return ObserverModePaywallHandlers(purchase: nil, restore: nil)
        }
        return ObserverModePaywallHandlers(
            purchase: { package in
                await purchase(
                    product: package.storeProduct.sk2Product,
                    productIdentifier: package.storeProduct.productIdentifier,
                    purchaseLogic: purchaseLogic,
                    recordPurchase: RevenueCatPaywall.recordPurchase
                )
            },
            restore: {
                await restore(
                    purchaseLogic: purchaseLogic,
                    syncPurchases: {
                        let info = try await Purchases.shared.syncPurchases()
                        return !info.activeSubscriptions.isEmpty || !info.nonSubscriptions.isEmpty
                    }
                )
            }
        )
    }

    static func purchase(
        product: Product?,
        productIdentifier: String = "unknown",
        purchaseLogic: RevenueCatPaywallPurchaseLogic?,
        recordPurchase: @escaping RecordPurchase
    ) async -> (userCancelled: Bool, error: Error?) {
        guard let purchaseLogic else {
            return (false, ObserverModePaywallError.purchaseLogicRequired)
        }
        guard let product else {
            return (false, ObserverModePaywallError.storeKit2ProductUnavailable(productIdentifier))
        }
        do {
            let result = try await purchaseLogic.purchase(product)
            return await completePurchase(result, recordPurchase: recordPurchase)
        } catch {
            return (false, error)
        }
    }

    static func completePurchase(
        _ purchaseResult: Product.PurchaseResult,
        recordPurchase: @escaping RecordPurchase
    ) async -> (userCancelled: Bool, error: Error?) {
        do {
            try await recordPurchase(purchaseResult)
            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return (false, nil)
                case .unverified(_, let error):
                    return (false, error)
                }
            case .userCancelled:
                return (true, nil)
            case .pending:
                return (false, ObserverModePaywallError.purchasePending)
            @unknown default:
                return (false, ObserverModePaywallError.purchasePending)
            }
        } catch {
            return (false, error)
        }
    }

    static func restore(
        purchaseLogic: RevenueCatPaywallPurchaseLogic?,
        syncPurchases: @escaping SyncPurchases
    ) async -> (success: Bool, error: Error?) {
        guard let purchaseLogic else {
            return (false, ObserverModePaywallError.purchaseLogicRequired)
        }
        do {
            try await purchaseLogic.restore()
            return (try await syncPurchases(), nil)
        } catch {
            return (false, error)
        }
    }
}
