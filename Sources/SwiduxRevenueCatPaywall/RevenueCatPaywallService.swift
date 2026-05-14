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
/// - Important: Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:)``
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
    public init(entitlementID: String, permanentLicenseEntitlementID: String? = nil) {
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
    /// Calls `Purchases.shared.restorePurchases()` and maps the resulting customer info.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting any entitlements restored to the account.
    /// - Throws: Any error propagated from `Purchases.shared.restorePurchases()`.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        let info = try await Purchases.shared.restorePurchases()
        return snapshot(from: info)
    }

    // MARK: - Internal

    func snapshot(from info: CustomerInfo) -> EntitlementSnapshot {
        Self.makeSnapshot(
            from: info,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
        )
    }

    /// Wraps an upstream `CustomerInfo` stream and yields a mapped `EntitlementSnapshot` for every
    /// value the upstream produces. Cancelling the consuming task cancels the upstream iteration.
    static func mapStream(
        _ upstream: AsyncStream<CustomerInfo>,
        entitlementID: String,
        permanentLicenseEntitlementID: String?
    ) -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
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
