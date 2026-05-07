//
//  RevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import RevenueCat
import SwiduxPaywall

/// RevenueCat implementation of `PaywallService`.
///
/// Delegates to `Purchases.shared` for customer-info fetches, real-time observation,
/// and purchase restoration. Maps `CustomerInfo` to `EntitlementSnapshot`.
///
/// The caller must configure `Purchases.configure(withAPIKey:)` before using this service.
public struct RevenueCatPaywallService: PaywallService {
    let entitlementID: String
    let permanentLicenseEntitlementID: String?

    /// Creates a service that checks the given entitlement identifiers.
    ///
    /// - Parameters:
    ///   - entitlementID: The RevenueCat entitlement identifier for pro access.
    ///   - permanentLicenseEntitlementID: Optional identifier for a lifetime/permanent entitlement.
    public init(entitlementID: String, permanentLicenseEntitlementID: String? = nil) {
        self.entitlementID = entitlementID
        self.permanentLicenseEntitlementID = permanentLicenseEntitlementID
    }

    /// Fetches the current customer info from RevenueCat and maps it to an `EntitlementSnapshot`.
    public func customerInfo() async throws -> EntitlementSnapshot {
        let info = try await Purchases.shared.customerInfo()
        return snapshot(from: info)
    }

    /// Returns a stream of entitlement snapshots derived from `Purchases.shared.customerInfoStream`.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        let entitlementID = self.entitlementID
        let permanentLicenseEntitlementID = self.permanentLicenseEntitlementID
        return AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    let snap = Self.makeSnapshot(
                        from: info,
                        entitlementID: entitlementID,
                        permanentLicenseEntitlementID: permanentLicenseEntitlementID
                    )
                    continuation.yield(snap)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Restores purchases via RevenueCat and returns the resulting `EntitlementSnapshot`.
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

    private static func makeSnapshot(
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
