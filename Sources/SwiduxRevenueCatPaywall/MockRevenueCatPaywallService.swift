//
//  MockRevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import SwiduxPaywall

/// Test and preview service with a controllable entitlement stream.
///
/// Unlike `MockPaywallService` from SwiduxPaywall (which finishes immediately),
/// this mock supports yielding entitlement transitions over time via its continuation.
public final class MockRevenueCatPaywallService: PaywallService, @unchecked Sendable {
    private let _snapshot: EntitlementSnapshot
    private let lock = NSLock()
    private var continuation: AsyncStream<EntitlementSnapshot>.Continuation?

    /// Creates a mock with an initial entitlement state.
    public init(isPro: Bool = false, hasPermanentLicense: Bool = false) {
        self._snapshot = EntitlementSnapshot(isPro: isPro, hasPermanentLicense: hasPermanentLicense)
    }

    public func customerInfo() async throws -> EntitlementSnapshot { _snapshot }

    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.yield(_snapshot)
        }
    }

    public func restorePurchases() async throws -> EntitlementSnapshot { _snapshot }

    /// Pushes an entitlement update to any active stream subscriber.
    public func send(_ snapshot: EntitlementSnapshot) {
        lock.withLock { _ = continuation?.yield(snapshot) }
    }

    /// Finishes the entitlement stream.
    public func finish() {
        lock.withLock { continuation?.finish() }
    }
}
