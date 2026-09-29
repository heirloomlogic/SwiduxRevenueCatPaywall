//
//  RevenueCatIdentityOperationGate.swift
//  SwiduxRevenueCatPaywall
//

/// Holds package identity operations through result mapping and error sampling, including SDK suspension points.
@MainActor
enum RevenueCatIdentityOperationGate {
    private static var isHeld = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    static func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
