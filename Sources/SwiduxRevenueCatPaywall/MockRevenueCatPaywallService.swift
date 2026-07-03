//
//  MockRevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import SwiduxPaywall

/// `PaywallService` conformer for previews and tests with a controllable entitlement stream.
///
/// Mirrors the real service's semantics: ``send(_:)`` updates the *current* snapshot, which is
/// what ``customerInfo()`` and ``restorePurchases()`` return and what a new
/// ``customerInfoStream()`` yields first. The stream then forwards every subsequent
/// ``send(_:)`` value and finishes when ``finish()`` is called. Set ``customerInfoError`` or
/// ``restoreError`` to make the corresponding call throw, e.g. to drive the plugin's
/// `.refreshFailed` path or a `ResilientPaywallService` fallback.
///
/// This is the key difference from `MockPaywallService` in SwiduxPaywall: that mock's stream
/// finishes immediately after the initial yield, so previews can't drive entitlement transitions
/// over time. This mock keeps the stream live, which lets tests simulate purchase, refund, and
/// family-share updates as a sequence.
///
/// - Note: Thread-safe via an internal `NSLock`. Marked `@unchecked Sendable` so it can be shared
///   across actors in tests and previews.
public final class MockRevenueCatPaywallService: PaywallService, @unchecked Sendable {
    private let lock = NSLock()
    private var current: EntitlementSnapshot
    private var customerInfoErrorStorage: Error?
    private var restoreErrorStorage: Error?
    private var continuation: AsyncStream<EntitlementSnapshot>.Continuation?
    // Identifies the active stream so a stale stream's onTermination (cancellation, finish of a
    // replaced stream) can't clear the continuation of a newer subscriber.
    private var streamGeneration = 0

    /// Creates a mock with a starting entitlement state.
    ///
    /// - Parameters:
    ///   - isPro: Initial value for `EntitlementSnapshot.isPro`. Defaults to `false`.
    ///   - hasPermanentLicense: Initial value for `EntitlementSnapshot.hasPermanentLicense`.
    ///     Defaults to `false`.
    public init(isPro: Bool = false, hasPermanentLicense: Bool = false) {
        self.current = EntitlementSnapshot(isPro: isPro, hasPermanentLicense: hasPermanentLicense)
    }

    /// Error thrown by ``customerInfo()`` while set. `nil` (the default) means success.
    ///
    /// Lets tests exercise failure paths — the paywall plugin's `.refreshFailed` action, retry
    /// affordances, or `ResilientPaywallService`'s last-known-good fallback.
    public var customerInfoError: Error? {
        get { lock.withLock { customerInfoErrorStorage } }
        set { lock.withLock { customerInfoErrorStorage = newValue } }
    }

    /// Error thrown by ``restorePurchases()`` while set. `nil` (the default) means success.
    public var restoreError: Error? {
        get { lock.withLock { restoreErrorStorage } }
        set { lock.withLock { restoreErrorStorage = newValue } }
    }

    /// Returns the current snapshot — the init-time state, or the latest value passed to
    /// ``send(_:)``.
    ///
    /// Throws ``customerInfoError`` instead when it is set. This matches the real service, whose
    /// `customerInfo()` reflects whatever RevenueCat last reported: the plugin's
    /// `.dismiss`-triggered refresh sees the same state the stream delivered.
    public func customerInfo() async throws -> EntitlementSnapshot {
        try lock.withLock {
            if let error = customerInfoErrorStorage { throw error }
            return current
        }
    }

    /// Returns a stream that yields the current snapshot, then any value passed to ``send(_:)``.
    ///
    /// The stream stays open until ``finish()`` is called. Each call to this method replaces the
    /// active continuation: the previous stream is finished (so an earlier subscriber's
    /// `for await` loop terminates instead of hanging), and only the most recent subscriber
    /// receives subsequent ``send(_:)`` updates.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
            // Install the continuation and yield the current snapshot in one critical section so
            // a concurrent send(_:) cannot slip its update in front of the first yield.
            let (previous, generation) = lock.withLock {
                streamGeneration += 1
                let previous = self.continuation
                self.continuation = continuation
                continuation.yield(current)
                return (previous, streamGeneration)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    if self.streamGeneration == generation { self.continuation = nil }
                }
            }
            // Finish outside the lock: finishing fires the replaced stream's onTermination
            // synchronously, which takes the lock itself.
            previous?.finish()
        }
    }

    /// Returns the current snapshot — the init-time state, or the latest value passed to
    /// ``send(_:)``.
    ///
    /// Throws ``restoreError`` instead when it is set.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        try lock.withLock {
            if let error = restoreErrorStorage { throw error }
            return current
        }
    }

    /// Updates the current snapshot and pushes it to the active stream subscriber.
    ///
    /// The snapshot becomes the value ``customerInfo()`` and ``restorePurchases()`` return, so a
    /// refresh after a simulated purchase sees the purchased state — the same as against the real
    /// service. If no stream has been requested yet (or the active stream has been finished), the
    /// snapshot is still recorded; only the stream delivery is skipped.
    ///
    /// - Parameter snapshot: The snapshot to make current and deliver to the active
    ///   ``customerInfoStream()`` subscriber.
    public func send(_ snapshot: EntitlementSnapshot) {
        lock.withLock {
            current = snapshot
            _ = continuation?.yield(snapshot)
        }
    }

    /// Finishes the active entitlement stream.
    ///
    /// Call this when the test or preview is done observing entitlement transitions so iterators
    /// terminate cleanly. Subsequent ``send(_:)`` calls still update the current snapshot but are
    /// no longer delivered to a stream.
    public func finish() {
        // Finish outside the lock: it fires onTermination synchronously, which takes the lock.
        let current = lock.withLock { continuation }
        current?.finish()
    }
}
