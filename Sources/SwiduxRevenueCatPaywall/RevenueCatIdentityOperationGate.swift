//
//  RevenueCatIdentityOperationGate.swift
//  SwiduxRevenueCatPaywall
//

import Synchronization

/// Queues package identity operations and fences entitlement results that overlap them.
///
/// Each login or logout holds its turn through result mapping and error sampling, including SDK suspension points. The generation advances whenever an operation takes its turn, so a fence recorded while no operation runs is broken by any operation that begins after it.
@MainActor
final class RevenueCatIdentityOperationGate: Sendable {
    /// The gate every package identity entry point shares, because RevenueCat has one process-wide identity.
    nonisolated static let shared = RevenueCatIdentityOperationGate()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private nonisolated let generation = Mutex<UInt64>(0)

    nonisolated init() {}

    func acquire() async {
        if isHeld {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isHeld = true
        }
        generation.withLock { $0 &+= 1 }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
            let idle = idleWaiters
            idleWaiters.removeAll()
            for waiter in idle { waiter.resume() }
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Waits until no identity operation is running, then records the generation and app user ID a result must still match to be delivered.
    func idleFence(appUserID: @escaping @Sendable () -> String) async -> Fence {
        while isHeld {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        return Fence(gate: self, generation: generation.withLock { $0 }, appUserID: appUserID)
    }

    /// The identity a read, restore, or stream subscription started under.
    struct Fence: Sendable {
        let gate: RevenueCatIdentityOperationGate
        let generation: UInt64
        let identity: String
        let appUserID: @Sendable () -> String

        init(gate: RevenueCatIdentityOperationGate, generation: UInt64, appUserID: @escaping @Sendable () -> String) {
            self.gate = gate
            self.generation = generation
            self.identity = appUserID()
            self.appUserID = appUserID
        }

        /// Whether no package identity operation has begun and the app user ID is unchanged since the fence was recorded.
        var holds: Bool {
            gate.generation.withLock { $0 == generation } && appUserID() == identity
        }
    }
}
