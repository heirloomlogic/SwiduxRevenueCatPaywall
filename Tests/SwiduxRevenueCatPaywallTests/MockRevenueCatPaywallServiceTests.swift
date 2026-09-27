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

// Stream tests await `next()`; the time limit turns a delivery regression into a failure
// instead of a CI job that hangs until its own timeout.
@Suite("MockRevenueCatPaywallService", .timeLimit(.minutes(1)))
struct MockRevenueCatPaywallServiceTests {
    @Test("Mock returns configured snapshot")
    func mockReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true)
        let snapshot = try await mock.customerInfo()
        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Mock stream yields initial snapshot")
    func mockStreamYieldsInitial() async throws {
        let mock = MockRevenueCatPaywallService(isPro: false, hasPermanentLicense: true)
        var snapshots: [EntitlementSnapshot] = []
        for await snapshot in mock.customerInfoStream() {
            snapshots.append(snapshot)
            break
        }
        #expect(snapshots.count == 1)
        let first = try #require(snapshots.first)
        #expect(first.hasPermanentLicense)
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

    @Test("Values sent before the consumer reads are all delivered, in order")
    func bufferedSendsArriveInOrder() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        var iterator = mock.customerInfoStream().makeAsyncIterator()

        mock.send(EntitlementSnapshot(isPro: true))
        mock.send(EntitlementSnapshot(isPro: true))
        mock.send(EntitlementSnapshot(isPro: false))
        mock.finish()

        var received: [Bool] = []
        while let snapshot = await iterator.next() {
            received.append(snapshot.isPro)
        }
        #expect(received == [false, true, true, false])
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

    @Test("Concurrent subscribers each receive the initial value and every send")
    func concurrentSubscribersFanOut() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        var first = mock.customerInfoStream().makeAsyncIterator()
        var second = mock.customerInfoStream().makeAsyncIterator()
        #expect(mock.activeSubscriberCount == 2)

        #expect(await first.next()?.isPro == false)
        #expect(await second.next()?.isPro == false)

        mock.send(EntitlementSnapshot(isPro: true))
        #expect(await first.next()?.isPro == true, "Opening a second stream must not cut off the first.")
        #expect(await second.next()?.isPro == true)

        mock.finish()
        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }

    @Test("finish ends the open streams; a stream opened afterwards is live")
    func finishThenNewStreamIsLive() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        var finished = mock.customerInfoStream().makeAsyncIterator()
        #expect(await finished.next()?.isPro == false)

        mock.finish()
        #expect(mock.activeSubscriberCount == 0)
        #expect(await finished.next() == nil)

        mock.send(EntitlementSnapshot(isPro: true))
        var fresh = mock.customerInfoStream().makeAsyncIterator()
        #expect(await fresh.next()?.isPro == true, "A post-finish stream yields the current snapshot.")

        mock.send(EntitlementSnapshot(isPro: false))
        #expect(await fresh.next()?.isPro == false, "A post-finish stream receives later sends.")
        #expect(await finished.next() == nil, "The finished stream stays finished.")

        mock.finish()
        #expect(await fresh.next() == nil)
    }

    @Test("Cancelling one subscriber's task leaves the other subscriber live")
    func cancellingOneSubscriberKeepsOthers() async {
        let mock = MockRevenueCatPaywallService(isPro: false)
        let cancelledStream = mock.customerInfoStream()
        var survivor = mock.customerInfoStream().makeAsyncIterator()

        // Signals once the consumer has taken the initial value, so the cancel lands while it is
        // suspended waiting for the next one.
        let (received, receivedSignal) = AsyncStream<Void>.makeStream()
        let consumer = Task {
            for await _ in cancelledStream {
                receivedSignal.yield()
            }
        }
        var receivedIterator = received.makeAsyncIterator()
        await receivedIterator.next()

        consumer.cancel()
        await consumer.value
        #expect(mock.activeSubscriberCount == 1, "Cancellation must unregister only its own stream.")

        #expect(await survivor.next()?.isPro == false)
        mock.send(EntitlementSnapshot(isPro: true))
        #expect(await survivor.next()?.isPro == true)

        mock.finish()
        #expect(await survivor.next() == nil)
    }

    @Test("Restore returns configured snapshot")
    func restoreReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true, hasPermanentLicense: true)
        let snapshot = try await mock.restorePurchases()
        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }
}
