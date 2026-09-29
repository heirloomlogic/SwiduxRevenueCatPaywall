//
//  RevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import OSLog
import RevenueCat
import SwiduxPaywall
import Synchronization

private let logger = Logger(
    subsystem: "com.heirloomlogic.SwiduxRevenueCatPaywall",
    category: "service"
)

/// `PaywallService` conformer backed by RevenueCat's `Purchases.shared`.
///
/// Maps `CustomerInfo.entitlements` to Swidux's `EntitlementSnapshot` by checking the configured
/// `entitlementID` for `isPro` and the optional `permanentLicenseEntitlementID` for
/// `hasPermanentLicense`. Forwards `Purchases.shared.customerInfoStream` so the paywall plugin
/// sees real-time entitlement changes.
///
/// A response whose entitlement signature fails verification is rejected: reads and restores
/// throw ``RevenueCatPaywallError/verificationFailed`` and the stream skips that response.
/// A `ResilientPaywallService` can then use its valid same-account cache as for a failed network
/// read. Cached RevenueCat responses older than five minutes retain access but use `.cache` or
/// `.cacheSeed` instead of `.live`, so they cannot renew the decorator's cache age.
///
/// - Important: Call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` before using the service. Construction is safe before configuration, but the service does not configure RevenueCat itself.
public struct RevenueCatPaywallService: PaywallService {
    private static let didLogConfigurationFault = Mutex(false)
    static let liveResponseWindow: TimeInterval = 5 * 60

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
    /// - Throws: ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/verificationFailed`` for a failed signature, or an SDK error.
    public func customerInfo() async throws -> EntitlementSnapshot {
        try Self.requireConfiguration()
        let info = try await Purchases.shared.customerInfo()
        return try snapshot(from: info, nonLiveSource: .cache)
    }

    /// Returns a long-lived stream of entitlement snapshots derived from
    /// `Purchases.shared.customerInfoStream`.
    ///
    /// Yields a new `EntitlementSnapshot` every time RevenueCat reports a change to the user's
    /// customer info — purchase, refund, family-share update, sandbox renewal. A failed-verification
    /// response is skipped. The stream
    /// finishes when the underlying RevenueCat stream finishes; the paywall plugin's
    /// `.observeCustomerInfo` effect normally keeps it alive for the duration of the session.
    ///
    /// A new stream first yields the customer info RevenueCat last delivered in this process, if
    /// any. RevenueCat may not have delivered one yet — on a relaunch with a fresh cache it skips
    /// the launch fetch — and then the stream stays silent until the next change. Dispatch
    /// `.refreshCustomerInfo` alongside `.observeCustomerInfo` to seed the state.
    ///
    /// If RevenueCat has not been configured, the stream finishes immediately. Configure RevenueCat, then call this method again to start a live stream.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        guard Self.isConfigured else {
            return AsyncStream { continuation in continuation.finish() }
        }
        return Self.mapStream(
            Purchases.shared.customerInfoStream,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
        )
    }

    /// Restores the user's purchases through RevenueCat.
    ///
    /// Calls RevenueCat's user-initiated `restorePurchases()` flow, which refreshes the App Store receipt before posting its transactions. This is also the correct path when the app owns purchases: `syncPurchases()` is for background migration and cannot recover a subscription that is absent from the device receipt.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting any entitlements restored to the account.
    /// - Throws: ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/verificationFailed`` for a failed signature, or an SDK error.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        try Self.requireConfiguration()
        let info = try await Purchases.shared.restorePurchases()
        return try snapshot(from: info, nonLiveSource: .cache)
    }

    // MARK: - Internal

    private static var isConfigured: Bool {
        guard Purchases.isConfigured else {
            logConfigurationFaultOnce()
            return false
        }
        return true
    }

    private static func requireConfiguration() throws(RevenueCatPaywallError) {
        guard isConfigured else { throw .notConfigured }
    }

    private static func logConfigurationFaultOnce() {
        let shouldLog = didLogConfigurationFault.withLock { didLog in
            guard !didLog else { return false }
            didLog = true
            return true
        }
        guard shouldLog else { return }
        logger.fault(
            """
            RevenueCatPaywallService was used before RevenueCat was configured. Call \
            RevenueCatPaywall.configure(apiKey:) before retrying.
            """
        )
    }

    func snapshot(
        from info: CustomerInfo, nonLiveSource: EntitlementSnapshot.Source
    ) throws(RevenueCatPaywallError) -> EntitlementSnapshot {
        try Self.makeSnapshot(
            from: info,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
            nonLiveSource: nonLiveSource
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
                    guard
                        let snapshot = try? makeSnapshot(
                            from: info,
                            entitlementID: entitlementID,
                            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
                            nonLiveSource: .cacheSeed
                        )
                    else { continue }
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makeSnapshot(
        from info: CustomerInfo,
        entitlementID: String,
        permanentLicenseEntitlementID: String?,
        nonLiveSource: EntitlementSnapshot.Source
    ) throws(RevenueCatPaywallError) -> EntitlementSnapshot {
        let pro = info.entitlements[entitlementID]
        let permanentLicense = permanentLicenseEntitlementID.flatMap { info.entitlements[$0] }
        let verifications = [info.entitlements.verification, pro?.verification, permanentLicense?.verification]
        guard !verifications.contains(.failed) else {
            logger.fault(
                """
                RevenueCat entitlement signature verification failed; the response is rejected.
                """
            )
            throw .verificationFailed
        }
        let isFresh = abs(info.requestDate.timeIntervalSinceNow) <= liveResponseWindow
        return EntitlementSnapshot(
            isPro: pro?.isActive == true,
            hasPermanentLicense: permanentLicense?.isActive == true,
            source: isFresh ? .live : nonLiveSource
        )
    }
}
