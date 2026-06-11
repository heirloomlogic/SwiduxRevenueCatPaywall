//
//  MockRevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import SwiduxPaywall

/// `PaywallService` conformer for previews and tests with a controllable entitlement stream.
///
/// Returns the snapshot configured at init from ``customerInfo()`` and ``restorePurchases()``.
/// Its stream yields the initial snapshot immediately, then forwards every value passed to
/// ``send(_:)``, and finishes when ``finish()`` is called.
///
/// This is the key difference from `MockPaywallService` in SwiduxPaywall: that mock's stream
/// finishes immediately after the initial yield, so previews can't drive entitlement transitions
/// over time. This mock keeps the stream live, which lets tests simulate purchase, refund, and
/// family-share updates as a sequence.
///
/// - Note: Thread-safe via an internal `NSLock`. Marked `@unchecked Sendable` so it can be shared
///   across actors in tests and previews.
public final class MockRevenueCatPaywallService: PaywallService, @unchecked Sendable {
    private let initialSnapshot: EntitlementSnapshot
    private let lock = NSLock()
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
        self.initialSnapshot = EntitlementSnapshot(isPro: isPro, hasPermanentLicense: hasPermanentLicense)
    }

    /// Returns the snapshot supplied at init.
    ///
    /// Updates pushed via ``send(_:)`` do **not** change the value returned here — only the
    /// stream reflects pushed updates. Use this when a test or preview needs a one-shot fetch.
    public func customerInfo() async throws -> EntitlementSnapshot { initialSnapshot }

    /// Returns a stream that yields the initial snapshot, then any value passed to ``send(_:)``.
    ///
    /// The stream stays open until ``finish()`` is called. Each call to this method replaces the
    /// active continuation: the previous stream is finished (so an earlier subscriber's
    /// `for await` loop terminates instead of hanging), and only the most recent subscriber
    /// receives subsequent ``send(_:)`` updates.
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        AsyncStream { continuation in
            let (previous, generation) = lock.withLock {
                streamGeneration += 1
                let previous = self.continuation
                self.continuation = continuation
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
            continuation.yield(initialSnapshot)
        }
    }

    /// Returns the snapshot supplied at init.
    ///
    /// Independent of the stream — the value returned here is not affected by ``send(_:)``
    /// or ``finish()``.
    public func restorePurchases() async throws -> EntitlementSnapshot { initialSnapshot }

    /// Pushes an entitlement snapshot to the active stream subscriber.
    ///
    /// No-op if no stream has been requested yet, or if the active stream has already been
    /// finished.
    ///
    /// - Parameter snapshot: The snapshot to deliver to the active ``customerInfoStream()``
    ///   subscriber.
    public func send(_ snapshot: EntitlementSnapshot) {
        lock.withLock { _ = continuation?.yield(snapshot) }
    }

    /// Finishes the active entitlement stream.
    ///
    /// Call this when the test or preview is done observing entitlement transitions so iterators
    /// terminate cleanly. Subsequent calls to ``send(_:)`` are no-ops.
    public func finish() {
        // Finish outside the lock: it fires onTermination synchronously, which takes the lock.
        let current = lock.withLock { continuation }
        current?.finish()
    }
}
