//
//  RevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import RevenueCat
import SwiduxPaywall

/// `PaywallService` conformer backed by RevenueCat's `Purchases.shared`.
///
/// Maps `CustomerInfo.entitlements` to Swidux's `EntitlementSnapshot` by checking the configured
/// `entitlementID` for `isPro` and the optional `permanentLicenseEntitlementID` for
/// `hasPermanentLicense`. Forwards `Purchases.shared.customerInfoStream` so the paywall plugin
/// sees real-time entitlement changes.
///
/// - Important: Call
///   ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
///   before constructing this service. The service does not configure RevenueCat itself.
public struct RevenueCatPaywallService: PaywallService {
    let entitlementID: String
    let permanentLicenseEntitlementID: String?

    /// Creates a service that maps RevenueCat entitlements to `EntitlementSnapshot`.
    ///
    /// - Parameters:
    ///   - entitlementID: RevenueCat entitlement identifier that grants pro access. Surfaces as
    ///     `EntitlementSnapshot.isPro` when active.
    ///   - permanentLicenseEntitlementID: Optional secondary identifier for a lifetime / permanent
    ///     entitlement. Surfaces as `EntitlementSnapshot.hasPermanentLicense` when active. Pass
    ///     `nil` if the app has no separate lifetime SKU.
    ///
    /// - Precondition: `RevenueCatPaywall.configure(apiKey:)` has been called. Without it, every
    ///   service method would trap inside the RevenueCat SDK at first use; failing here instead
    ///   names the fix. Previews and tests should construct ``MockRevenueCatPaywallService``.
    public init(entitlementID: String, permanentLicenseEntitlementID: String? = nil) {
        precondition(
            Purchases.isConfigured,
            """
            Call RevenueCatPaywall.configure(apiKey:) before constructing \
            RevenueCatPaywallService. Previews and tests should use \
            MockRevenueCatPaywallService instead.
            """
        )
        self.entitlementID = entitlementID
        self.permanentLicenseEntitlementID = permanentLicenseEntitlementID
    }

    /// Fetches the current entitlement snapshot from RevenueCat.
    ///
    /// Calls `Purchases.shared.customerInfo()` and maps the result against the configured
    /// entitlement identifiers.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting the configured entitlement IDs.
    /// - Throws: Any error propagated from `Purchases.shared.customerInfo()`.
    public func customerInfo() async throws -> EntitlementSnapshot {
        let info = try await Purchases.shared.customerInfo()
        return snapshot(from: info)
    }

    /// Returns a long-lived stream of entitlement snapshots derived from
    /// `Purchases.shared.customerInfoStream`.
    ///
    /// Yields a new `EntitlementSnapshot` every time RevenueCat reports a change to the user's
    /// customer info — purchase, refund, family-share update, sandbox renewal. The stream
    /// finishes when the underlying RevenueCat stream finishes; the paywall plugin's
    /// `.observeCustomerInfo` effect normally keeps it alive for the duration of the session.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        Self.mapStream(
            Purchases.shared.customerInfoStream,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
        )
    }

    /// Restores the user's purchases through RevenueCat.
    ///
    /// Branches on the SDK's live `purchasesAreCompletedBy` mode, read at call time: in observer
    /// mode (`.myApp`) the SDK's `restorePurchases()` can alias or transfer purchases between app
    /// user IDs, so this calls `syncPurchases()` — RevenueCat's documented equivalent there —
    /// while the default (`.revenueCat`) mode calls `restorePurchases()`. Either way the resulting
    /// customer info is mapped to a snapshot.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting any entitlements restored to the account.
    /// - Throws: Any error propagated from the underlying SDK call.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        let info: CustomerInfo
        switch Self.restoreStrategy(for: Purchases.shared.purchasesAreCompletedBy) {
        case .sync: info = try await Purchases.shared.syncPurchases()
        case .restore: info = try await Purchases.shared.restorePurchases()
        }
        return snapshot(from: info)
    }

    // MARK: - Internal

    /// Which SDK call ``restorePurchases()`` should make for a given completion mode.
    enum RestoreStrategy: Equatable { case restore, sync }

    /// Selects the restore call appropriate to the SDK's completion mode.
    ///
    /// In observer mode (`purchasesAreCompletedBy == .myApp`) the SDK's `restorePurchases()` can
    /// alias or transfer purchases between app user IDs; RevenueCat documents `syncPurchases()` as
    /// the correct equivalent there. Every other mode uses `restorePurchases()`. Kept pure so the
    /// branch is unit-testable — `Purchases.configure` is once-per-process, so only one end-to-end
    /// configure path can ever run in a test suite.
    static func restoreStrategy(for completedBy: PurchasesAreCompletedBy) -> RestoreStrategy {
        completedBy == .myApp ? .sync : .restore
    }

    func snapshot(from info: CustomerInfo) -> EntitlementSnapshot {
        Self.makeSnapshot(
            from: info,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
        )
    }

    /// Wraps an upstream `CustomerInfo` stream and yields a mapped `EntitlementSnapshot` for every
    /// value the upstream produces. Cancelling the consuming task cancels the upstream iteration.
    ///
    /// Buffers only the newest snapshot: each yield is a complete entitlement state, so a slow
    /// consumer should see the latest value rather than replay stale intermediate states.
    static func mapStream(
        _ upstream: AsyncStream<CustomerInfo>,
        entitlementID: String,
        permanentLicenseEntitlementID: String?
    ) -> AsyncStream<EntitlementSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await info in upstream {
                    continuation.yield(
                        makeSnapshot(
                            from: info,
                            entitlementID: entitlementID,
                            permanentLicenseEntitlementID: permanentLicenseEntitlementID
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makeSnapshot(
        from info: CustomerInfo,
        entitlementID: String,
        permanentLicenseEntitlementID: String?
    ) -> EntitlementSnapshot {
        EntitlementSnapshot(
            isPro: info.entitlements[entitlementID]?.isActive == true,
            hasPermanentLicense: permanentLicenseEntitlementID.flatMap {
                info.entitlements[$0]?.isActive
            } == true
        )
    }
}
