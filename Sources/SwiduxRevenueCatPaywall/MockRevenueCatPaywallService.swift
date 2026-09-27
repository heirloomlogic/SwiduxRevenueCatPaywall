//
//  MockRevenueCatPaywallService.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import SwiduxPaywall
import Synchronization

/// `PaywallService` conformer for previews and tests with a controllable entitlement stream.
///
/// The mock tracks a *current* snapshot: ``send(_:)`` replaces it, ``customerInfo()`` and
/// ``restorePurchases()`` return it, and every ``customerInfoStream()`` yields it first. Streams
/// fan out — each call returns an independent stream, and ``send(_:)`` delivers to every stream
/// that is still open — so two stores sharing one mock, or a `ResilientPaywallService` wrapper
/// plus the paywall plugin, all observe the same transitions. ``finish()`` ends the streams that
/// are open at the time. Set ``customerInfoError`` or ``restoreError`` to make the corresponding
/// call throw, e.g. to drive the plugin's `.refreshFailed` path or a `ResilientPaywallService`
/// fallback.
///
/// Deliberate differences from the real `RevenueCatPaywallService`, chosen so tests are
/// deterministic:
/// - A stream buffers every value it has not delivered yet; the real stream keeps only the
///   newest. A test that sends several snapshots before its consumer runs sees each one, in order.
/// - A new stream always yields the current snapshot first; the real stream yields a first value
///   only if RevenueCat has already delivered customer info in this process.
///
/// Compared with Swidux's `SimulatedPaywallService` (an actor with a dev-paywall UI and simulated
/// latency, better suited to vendor-free previews and development builds), this mock offers a
/// synchronous ``send(_:)``, arbitrary injected errors, ``finish()``, and delivery of repeated
/// identical snapshots — `SimulatedPaywallService` drops a change that equals the current state.
/// `MockPaywallService` in SwiduxPaywall differs again: its stream finishes immediately after the
/// initial yield, so it cannot drive entitlement transitions over time.
///
/// - Note: Thread-safe. State lives behind a `Synchronization.Mutex`, so the type is checked
///   `Sendable` and can be shared across actors in tests and previews.
public final class MockRevenueCatPaywallService: PaywallService, Sendable {
    private struct State {
        var current: EntitlementSnapshot
        var customerInfoError: (any Error)?
        var restoreError: (any Error)?
        var subscribers: [UUID: AsyncStream<EntitlementSnapshot>.Continuation] = [:]
    }

    private let state: Mutex<State>

    /// Creates a mock with a starting entitlement state.
    ///
    /// - Parameters:
    ///   - isPro: Initial value for `EntitlementSnapshot.isPro`. Defaults to `false`.
    ///   - hasPermanentLicense: Initial value for `EntitlementSnapshot.hasPermanentLicense`.
    ///     Defaults to `false`.
    public init(isPro: Bool = false, hasPermanentLicense: Bool = false) {
        self.state = Mutex(
            State(current: EntitlementSnapshot(isPro: isPro, hasPermanentLicense: hasPermanentLicense))
        )
    }

    /// Error thrown by ``customerInfo()`` while set. `nil` (the default) means success.
    ///
    /// Lets tests exercise failure paths — the paywall plugin's `.refreshFailed` action, retry
    /// affordances, or `ResilientPaywallService`'s last-known-good fallback.
    public var customerInfoError: (any Error)? {
        get { state.withLock { $0.customerInfoError } }
        set { state.withLock { $0.customerInfoError = newValue } }
    }

    /// Error thrown by ``restorePurchases()`` while set. `nil` (the default) means success.
    public var restoreError: (any Error)? {
        get { state.withLock { $0.restoreError } }
        set { state.withLock { $0.restoreError = newValue } }
    }

    /// Number of streams currently registered for ``send(_:)`` delivery. Test-only visibility.
    var activeSubscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    /// Returns the current snapshot — the init-time state, or the latest value passed to
    /// ``send(_:)``.
    ///
    /// Throws ``customerInfoError`` instead when it is set. Like the real service, whose
    /// `customerInfo()` reflects whatever RevenueCat last reported, the plugin's
    /// `.dismiss`-triggered refresh sees the same state the stream delivered.
    public func customerInfo() async throws -> EntitlementSnapshot {
        try state.withLock { state in
            if let error = state.customerInfoError { throw error }
            return state.current
        }
    }

    /// Returns a new stream that yields the current snapshot, then every value passed to
    /// ``send(_:)``.
    ///
    /// Each call returns an independent stream; every open stream receives every ``send(_:)``.
    /// A stream ends when ``finish()`` is called while it is open, or when its consumer cancels
    /// or drops it — which unregisters it without affecting other streams.
    ///
    /// The stream uses the default unbounded buffering on purpose: a test that sends several
    /// snapshots before its consumer runs observes every transition, in order. (The real service
    /// buffers only the newest value.)
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            // Install the termination handler before the continuation is reachable from `state`:
            // once published, a concurrent finish() may terminate it, and a handler installed
            // after that would never run, leaving a dead continuation registered.
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
            }
            // Register and yield the current snapshot in one critical section so a concurrent
            // send(_:) cannot deliver its update ahead of the first value.
            state.withLock { state in
                state.subscribers[id] = continuation
                continuation.yield(state.current)
            }
        }
    }

    /// Returns the current snapshot — the init-time state, or the latest value passed to
    /// ``send(_:)``.
    ///
    /// Throws ``restoreError`` instead when it is set.
    public func restorePurchases() async throws -> EntitlementSnapshot {
        try state.withLock { state in
            if let error = state.restoreError { throw error }
            return state.current
        }
    }

    /// Makes `snapshot` current and delivers it to every open ``customerInfoStream()``.
    ///
    /// The snapshot becomes the value ``customerInfo()`` and ``restorePurchases()`` return, so a
    /// refresh after a simulated purchase sees the purchased state — the same as against the real
    /// service. With no open stream the snapshot is still recorded, and the next stream yields it
    /// first. Identical consecutive snapshots are each delivered.
    ///
    /// - Parameter snapshot: The snapshot to make current and deliver.
    public func send(_ snapshot: EntitlementSnapshot) {
        state.withLock { state in
            state.current = snapshot
            // Yielding under the lock is safe: AsyncStream's yield only buffers the value or
            // resumes a waiting consumer; it never runs onTermination (only finish(), consumer
            // cancellation, and storage deinit do), so it cannot re-enter this lock.
            for continuation in state.subscribers.values {
                continuation.yield(snapshot)
            }
        }
    }

    /// Finishes every stream that is open when called.
    ///
    /// Consumers receive any values still buffered, then their `for await` loops end. Call this
    /// when a test or preview is done observing entitlement transitions. The mock stays usable:
    /// ``send(_:)`` keeps updating the current snapshot, and a ``customerInfoStream()`` requested
    /// afterwards is a fresh, live stream that yields the current snapshot and later sends.
    public func finish() {
        let finishing = state.withLock { state in
            let continuations = Array(state.subscribers.values)
            state.subscribers.removeAll()
            return continuations
        }
        // Finish outside the lock: finish() runs onTermination synchronously, which takes it.
        for continuation in finishing {
            continuation.finish()
        }
    }
}
