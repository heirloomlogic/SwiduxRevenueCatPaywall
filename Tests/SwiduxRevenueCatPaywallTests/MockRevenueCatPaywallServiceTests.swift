//
//  MockRevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

/// Sentinel error the mock throws so tests can assert on a specific, unambiguous type.
private struct TestError: Error {}

@Suite("MockRevenueCatPaywallService")
struct MockRevenueCatPaywallServiceTests {
    @Test("Mock returns configured snapshot")
    func mockReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true)
        let snapshot = try await mock.customerInfo()
        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Mock stream yields initial snapshot")
    func mockStreamYieldsInitial() async {
        let mock = MockRevenueCatPaywallService(isPro: false, hasPermanentLicense: true)
        var snapshots: [EntitlementSnapshot] = []
        for await snapshot in mock.customerInfoStream() {
            snapshots.append(snapshot)
            break
        }
        #expect(snapshots.count == 1)
        #expect(snapshots[0].hasPermanentLicense)
    }

    @Test("Mock send pushes updates to stream")
    func mockSendPushesUpdates() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        let stream = mock.customerInfoStream()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial?.isPro == false)

        mock.send(EntitlementSnapshot(isPro: true))
        let updated = await iterator.next()
        #expect(updated?.isPro == true)

        mock.finish()
    }

    @Test("send updates the snapshot returned by customerInfo and restorePurchases")
    func sendUpdatesCurrentSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: false)

        mock.send(EntitlementSnapshot(isPro: true))

        // The plugin refreshes via customerInfo() when the paywall is dismissed; a refresh after
        // a simulated purchase must not regress the gate to the init-time state.
        let refreshed = try await mock.customerInfo()
        #expect(refreshed.isPro)
        let restored = try await mock.restorePurchases()
        #expect(restored.isPro)
    }

    @Test("A stream requested after send yields the current snapshot first")
    func streamAfterSendYieldsCurrent() async {
        let mock = MockRevenueCatPaywallService(isPro: false)

        mock.send(EntitlementSnapshot(isPro: true))
        var iterator = mock.customerInfoStream().makeAsyncIterator()

        let first = await iterator.next()
        #expect(first?.isPro == true)

        mock.finish()
    }

    @Test("customerInfoError makes customerInfo throw; clearing it restores success")
    func customerInfoErrorInjection() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true)

        mock.customerInfoError = TestError()
        await #expect(throws: TestError.self) {
            try await mock.customerInfo()
        }

        mock.customerInfoError = nil
        let snapshot = try await mock.customerInfo()
        #expect(snapshot.isPro)
    }

    @Test("restoreError makes restorePurchases throw without affecting customerInfo")
    func restoreErrorInjection() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true)

        mock.restoreError = TestError()
        await #expect(throws: TestError.self) {
            try await mock.restorePurchases()
        }

        let snapshot = try await mock.customerInfo()
        #expect(snapshot.isPro)
    }

    @Test("Mock finish terminates the stream")
    func mockFinishTerminatesStream() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        let stream = mock.customerInfoStream()
        var iterator = stream.makeAsyncIterator()

        _ = await iterator.next()  // initial snapshot
        mock.finish()

        let terminal = await iterator.next()
        #expect(terminal == nil)
    }

    @Test("Requesting a second stream finishes the first")
    func secondStreamFinishesFirst() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        var firstIterator = mock.customerInfoStream().makeAsyncIterator()
        _ = await firstIterator.next()  // initial snapshot

        var secondIterator = mock.customerInfoStream().makeAsyncIterator()

        let firstTerminal = await firstIterator.next()
        #expect(firstTerminal == nil, "Replaced stream must finish, not strand its subscriber.")

        _ = await secondIterator.next()  // initial snapshot
        mock.send(EntitlementSnapshot(isPro: true))
        let updated = await secondIterator.next()
        #expect(updated?.isPro == true, "Newest subscriber must keep receiving send(_:) updates.")

        mock.finish()
    }

    @Test("Restore returns configured snapshot")
    func restoreReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true, hasPermanentLicense: true)
        let snapshot = try await mock.restorePurchases()
        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }
}
