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
    let identityGate: RevenueCatIdentityOperationGate

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
        self.init(
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
            identityGate: .shared
        )
    }

    /// Tests pass a private gate so identity operations in parallel suites cannot interfere. Every
    /// production path, including the deprecated namespace methods, uses `.shared`.
    init(
        entitlementID: String,
        permanentLicenseEntitlementID: String?,
        identityGate: RevenueCatIdentityOperationGate
    ) {
        self.entitlementID = entitlementID
        self.permanentLicenseEntitlementID = permanentLicenseEntitlementID
        self.identityGate = identityGate
    }

    /// Switches RevenueCat to an application user and returns that user's mapped entitlements.
    ///
    /// Failed signature verification is rejected. Configuring verification as `.disabled` accepts responses without a signature check.
    ///
    /// - Parameter appUserID: The stable identifier for the signed-in user.
    /// - Returns: The identity observed after login and the mapped entitlement snapshot returned by RevenueCat.
    /// - Throws: ``RevenueCatPaywallIdentityError``. Inspect `identityChanged` and `identityAfter` before deciding whether to keep or discard account-scoped state because RevenueCat can change identity before a later request fails.
    @MainActor
    public func logIn(
        appUserID: String
    ) async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult {
        guard Self.isConfigured else {
            throw RevenueCatPaywallIdentityError(
                operation: .logIn,
                reason: .notConfigured,
                identityBefore: nil,
                identityAfter: nil
            )
        }
        let purchases = Purchases.shared
        return try await logIn(
            currentIdentity: { Self.identity(of: purchases) },
            operation: { try await purchases.logIn(appUserID).customerInfo }
        )
    }

    /// Switches RevenueCat to an anonymous user and returns that user's mapped entitlements.
    ///
    /// Failed signature verification is rejected. Configuring verification as `.disabled` accepts responses without a signature check.
    ///
    /// When the current identity is already anonymous, this method does not call RevenueCat's logout operation. It returns a cached snapshot accepted by the verification policy when one is available; `snapshot` is otherwise `nil`.
    ///
    /// - Returns: The identity observed after logout and the mapped entitlement snapshot returned by RevenueCat.
    /// - Throws: ``RevenueCatPaywallIdentityError``. Inspect `identityChanged` and `identityAfter` before deciding whether to keep or discard account-scoped state because RevenueCat can change identity before a later request fails.
    @MainActor
    public func logOut() async throws(RevenueCatPaywallIdentityError)
        -> RevenueCatPaywallIdentityResult
    {
        guard Self.isConfigured else {
            throw RevenueCatPaywallIdentityError(
                operation: .logOut,
                reason: .notConfigured,
                identityBefore: nil,
                identityAfter: nil
            )
        }
        let purchases = Purchases.shared
        return try await logOut(
            currentIdentity: { Self.identity(of: purchases) },
            cachedCustomerInfo: { purchases.cachedCustomerInfo },
            operation: { try await purchases.logOut() }
        )
    }

    /// Fetches the current entitlement snapshot from RevenueCat.
    ///
    /// Calls `Purchases.shared.customerInfo()` and maps the result against the configured
    /// entitlement identifiers.
    ///
    /// A read that starts while a package login or logout is running waits for it to finish. A result that arrives after another identity operation began, or after the RevenueCat app user ID changed, is discarded.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting the configured entitlement IDs.
    /// - Throws: ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/identityChanged`` when the identity changed during the read, ``RevenueCatPaywallError/verificationFailed`` for a failed signature, or an SDK error.
    public func customerInfo() async throws -> EntitlementSnapshot {
        try Self.requireConfiguration()
        let purchases = Purchases.shared
        return try await fencedSnapshot(
            appUserID: { purchases.appUserID },
            fetch: { try await purchases.customerInfo() }
        )
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
    ///
    /// The stream stays open across package logins and logouts but never forwards a value that could belong to the previous identity. When a package identity operation begins, or the RevenueCat app user ID changes, the stream discards its RevenueCat subscription with anything still buffered in it. Once no identity operation is running, it subscribes again, and the new subscription starts from the customer info RevenueCat holds for the new identity.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        guard Self.isConfigured else {
            return AsyncStream { continuation in continuation.finish() }
        }
        let purchases = Purchases.shared
        return Self.mapStream(
            subscribe: { purchases.customerInfoStream },
            appUserID: { purchases.appUserID },
            identityGate: identityGate,
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
        )
    }

    /// Restores the user's purchases through RevenueCat.
    ///
    /// Calls RevenueCat's user-initiated `restorePurchases()` flow, which refreshes the App Store receipt before posting its transactions. This is also the correct path when the app owns purchases: `syncPurchases()` is for background migration and cannot recover a subscription that is absent from the device receipt.
    ///
    /// A restore follows the same identity rule as ``customerInfo()``: it waits for a running package login or logout, and its result is discarded if the identity changes before it returns.
    ///
    /// - Returns: An `EntitlementSnapshot` reflecting any entitlements restored to the account.
    /// - Throws: ``RevenueCatPaywallError/notConfigured`` before configuration, ``RevenueCatPaywallError/identityChanged`` when the identity changed during the restore, ``RevenueCatPaywallError/verificationFailed`` for a failed signature, or an SDK error.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        try Self.requireConfiguration()
        let purchases = Purchases.shared
        return try await fencedSnapshot(
            appUserID: { purchases.appUserID },
            fetch: { try await purchases.restorePurchases() }
        )
    }

    // MARK: - Internal

    @MainActor
    func logIn(
        currentIdentity: () -> RevenueCatPaywallIdentity,
        operation: () async throws -> CustomerInfo
    ) async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult {
        await identityGate.acquire()
        defer { identityGate.release() }
        let identityBefore = currentIdentity()
        return try await performIdentityOperation(
            .logIn,
            identityBefore: identityBefore,
            currentIdentity: currentIdentity,
            operation: operation
        )
    }

    @MainActor
    func logOut(
        currentIdentity: () -> RevenueCatPaywallIdentity,
        cachedCustomerInfo: () -> CustomerInfo?,
        operation: () async throws -> CustomerInfo
    ) async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult {
        await identityGate.acquire()
        defer { identityGate.release() }
        let identityBefore = currentIdentity()
        guard identityBefore != .anonymous else {
            let cachedSnapshot: EntitlementSnapshot?
            if let info = cachedCustomerInfo() {
                cachedSnapshot = try? snapshot(from: info, nonLiveSource: .cache)
            } else {
                cachedSnapshot = nil
            }
            return RevenueCatPaywallIdentityResult(
                identity: .anonymous,
                snapshot: cachedSnapshot,
                identityChanged: false
            )
        }
        return try await performIdentityOperation(
            .logOut,
            identityBefore: identityBefore,
            currentIdentity: currentIdentity,
            operation: operation
        )
    }

    /// Maps a read or restore, discarding a result that may belong to a different identity than
    /// the one active when it started.
    func fencedSnapshot(
        appUserID: @escaping @Sendable () -> String,
        fetch: @Sendable () async throws -> CustomerInfo
    ) async throws -> EntitlementSnapshot {
        let fence = await identityGate.idleFence(appUserID: appUserID)
        let info = try await fetch()
        guard fence.holds else { throw RevenueCatPaywallError.identityChanged }
        return try snapshot(from: info, nonLiveSource: .cache)
    }

    @MainActor
    private func performIdentityOperation(
        _ operationKind: RevenueCatPaywallIdentityError.Operation,
        identityBefore: RevenueCatPaywallIdentity,
        currentIdentity: () -> RevenueCatPaywallIdentity,
        operation: () async throws -> CustomerInfo
    ) async throws(RevenueCatPaywallIdentityError) -> RevenueCatPaywallIdentityResult {
        do {
            let info = try await operation()
            let snapshot = try snapshot(from: info, nonLiveSource: .cache)
            let identityAfter = currentIdentity()
            return RevenueCatPaywallIdentityResult(
                identity: identityAfter,
                snapshot: snapshot,
                identityChanged: identityBefore != identityAfter
            )
        } catch {
            throw RevenueCatPaywallIdentityError(
                operation: operationKind,
                reason: Self.identityFailureReason(from: error),
                identityBefore: identityBefore,
                identityAfter: currentIdentity()
            )
        }
    }

    private static func identity(of purchases: Purchases) -> RevenueCatPaywallIdentity {
        purchases.isAnonymous ? .anonymous : .appUserID(purchases.appUserID)
    }

    static func identityFailureReason(
        from error: any Error
    ) -> RevenueCatPaywallIdentityError.Reason {
        if error as? RevenueCatPaywallError == .verificationFailed {
            return .verificationFailed
        }
        let nsError = error as NSError
        guard nsError.domain == ErrorCode.errorDomain, let code = ErrorCode(rawValue: nsError.code)
        else {
            return .providerFailure
        }
        switch code {
        case .invalidAppUserIdError:
            return .invalidAppUserID
        case .networkError, .offlineConnectionError, .apiEndpointBlockedError:
            return .networkUnavailable
        case .signatureVerificationFailed:
            return .verificationFailed
        case .configurationError, .invalidCredentialsError:
            return .configuration
        default:
            return .providerFailure
        }
    }

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

    /// Subscribes to an upstream `CustomerInfo` stream and yields a mapped `EntitlementSnapshot`
    /// for every value the upstream produces, resubscribing across identity changes as
    /// ``customerInfoStream()`` describes. Cancelling the consuming task cancels the upstream
    /// iteration.
    ///
    /// Buffers only the newest snapshot: each yield is a complete entitlement state, so a slow
    /// consumer should see the latest value rather than replay stale intermediate states.
    static func mapStream(
        subscribe: @escaping @Sendable () -> AsyncStream<CustomerInfo>,
        appUserID: @escaping @Sendable () -> String,
        identityGate: RevenueCatIdentityOperationGate,
        entitlementID: String,
        permanentLicenseEntitlementID: String?
    ) -> AsyncStream<EntitlementSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                subscriptions: while !Task.isCancelled {
                    let fence = await identityGate.idleFence(appUserID: appUserID)
                    // Leaving this loop releases the upstream stream, which ends RevenueCat's
                    // subscription and discards whatever it still buffers.
                    for await info in subscribe() {
                        if !fence.holds { continue subscriptions }
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
                    break
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
