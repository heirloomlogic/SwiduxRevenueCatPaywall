//
//  RevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import Swidux
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

/// Sentinel error the mock throws so tests can assert on a specific, unambiguous type.
private struct TestError: Error {}

// Mapping tests go through the static `makeSnapshot` rather than a service instance:
// `RevenueCatPaywallService.init` preconditions on `Purchases.isConfigured`, and configuring the
// real SDK is reserved for the single end-to-end test in RevenueCatPaywallConfigurationTests.
@Suite("RevenueCatPaywallService entitlement mapping")
struct RevenueCatPaywallServiceTests {
    private func makeSnapshot(
        entitlements: [String: EntitlementInfo],
        entitlementID: String = "pro",
        permanentLicenseEntitlementID: String? = nil
    ) throws -> EntitlementSnapshot {
        try RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(entitlements: entitlements),
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
            nonLiveSource: .cache
        )
    }

    @Test("Active pro entitlement maps to isPro=true")
    func activeProMapsToIsPro() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]
        )

        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Inactive pro entitlement maps to isPro=false")
    func inactiveProMapsToFalse() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: false)]
        )

        #expect(!snapshot.isPro)
    }

    @Test("Missing pro entitlement maps to isPro=false")
    func missingProMapsToFalse() throws {
        let snapshot = try makeSnapshot(entitlements: [:])

        #expect(!snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Active permanent-license entitlement sets hasPermanentLicense=true")
    func activeLifetimeMapsToPermanentLicense() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: true)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(!snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }

    @Test("Lifetime entitlement is ignored when no permanent-license ID is configured")
    func lifetimeIgnoredWhenNoIDConfigured() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: true)]
        )

        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Both pro and lifetime active sets both flags")
    func bothActiveSetsBothFlags() throws {
        let snapshot = try makeSnapshot(
            entitlements: [
                "pro": makeEntitlement(id: "pro", isActive: true),
                "lifetime": makeEntitlement(id: "lifetime", isActive: true),
            ],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }

    @Test("Pro active with lifetime absent sets only isPro when both IDs are configured")
    func proActiveLifetimeAbsentSetsOnlyIsPro() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Inactive permanent-license entitlement keeps hasPermanentLicense=false")
    func inactiveLifetimeKeepsFalse() throws {
        let snapshot = try makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: false)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(!snapshot.hasPermanentLicense)
    }
}

// A tampered response is exactly what verification exists to catch, and apps never see
// `CustomerInfo` — the adapter is the only place the verification result can be acted on. A
// rejected read must look like any other failed read, so `ResilientPaywallService` falls back to
// its last-known-good instead of the plugin flipping a paying user to free.
@Suite("RevenueCatPaywallService entitlement verification")
struct EntitlementVerificationTests {
    private let forged = makeCustomerInfo(
        entitlements: [
            "pro": makeEntitlement(id: "pro", isActive: true, verification: .failed),
            "lifetime": makeEntitlement(id: "lifetime", isActive: true, verification: .failed),
        ],
        verification: .failed
    )

    @Test(
        "Verified, on-device-verified, and unrequested results grant as live",
        arguments: [VerificationResult.verified, .verifiedOnDevice, .notRequested]
    )
    func trustedResultsGrant(_ verification: VerificationResult) throws {
        let snapshot = try RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true, verification: verification)],
                verification: verification
            ),
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil,
            nonLiveSource: .cache
        )

        #expect(snapshot.isPro)
        #expect(snapshot.source == .live)
    }

    @Test("A response that failed verification is rejected, not mapped")
    func failedResponseIsRejected() {
        #expect(throws: RevenueCatPaywallError.verificationFailed) {
            try RevenueCatPaywallService.makeSnapshot(
                from: forged,
                entitlementID: "pro",
                permanentLicenseEntitlementID: "lifetime",
                nonLiveSource: .cache
            )
        }
    }

    @Test("A forged read with nothing cached fails, and nothing is cached")
    func forgedReadWithEmptyCacheFails() async {
        let store = InMemoryKeyValueStore()
        let resilient = ResilientPaywallService(
            base: ReadOnlyPaywallService(info: forged, permanentLicenseEntitlementID: "lifetime"),
            store: store,
            maxAttempts: 1
        )

        await #expect(throws: RevenueCatPaywallError.verificationFailed) { try await resilient.customerInfo() }
        #expect(store.value(.lastKnownEntitlement) == nil)
    }

    @Test("A forged entitlement fails the read even when the response-level result is not failed")
    func forgedEntitlementFailsRead() async {
        let resilient = ResilientPaywallService(
            base: ReadOnlyPaywallService(
                info: makeCustomerInfo(
                    entitlements: ["pro": makeEntitlement(id: "pro", isActive: true, verification: .failed)],
                    verification: .verified
                ),
                permanentLicenseEntitlementID: nil
            ),
            store: InMemoryKeyValueStore(),
            maxAttempts: 1
        )

        await #expect(throws: RevenueCatPaywallError.verificationFailed) { try await resilient.customerInfo() }
    }

    @Test("A forged read falls back to a cached pro entitlement and leaves the cache untouched")
    func forgedReadFallsBackToCache() async throws {
        let store = InMemoryKeyValueStore()
        let cachedAt = Date().addingTimeInterval(-3600)
        store.setValue(
            CachedEntitlement(isPro: true, hasPermanentLicense: false, cachedAt: cachedAt),
            for: .lastKnownEntitlement
        )
        let resilient = ResilientPaywallService(
            base: ReadOnlyPaywallService(info: forged, permanentLicenseEntitlementID: "lifetime"),
            store: store,
            maxAttempts: 1
        )

        let snapshot = try await resilient.customerInfo()

        #expect(snapshot == EntitlementSnapshot(isPro: true, source: .cache))
        #expect(store.value(.lastKnownEntitlement)?.cachedAt == cachedAt)
        #expect(store.value(.lastKnownEntitlement)?.isPro == true)
    }

    @Test("A forged stream value is dropped and never reaches ResilientPaywallService's cache")
    func forgedStreamValueIsDropped() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let store = InMemoryKeyValueStore()
        let resilient = ResilientPaywallService(
            base: StreamOnlyPaywallService(
                stream: RevenueCatPaywallService.mapStream(
                    upstream,
                    entitlementID: "pro",
                    permanentLicenseEntitlementID: "lifetime"
                )
            ),
            store: store
        )
        var iterator = resilient.customerInfoStream().makeAsyncIterator()

        // Finishing right behind the forged value makes "dropped" observable as the stream ending
        // with nothing yielded, rather than as a race against a later genuine value.
        continuation.yield(forged)
        continuation.finish()
        let first = await iterator.next()

        #expect(first == nil, "The forged value must be skipped, not mapped.")
        #expect(store.value(.lastKnownEntitlement) == nil)
    }
}

// RevenueCat replays its last-known (often disk-cached) `CustomerInfo` when a stream starts, and
// `customerInfo()` returns cached info by default. Labelling that `.live` would let
// `ResilientPaywallService` re-stamp its own cache as fresh from RevenueCat's cache on every launch.
@Suite("RevenueCatPaywallService response freshness")
struct ResponseFreshnessTests {
    private func makeSnapshot(
        requestedAgo age: TimeInterval,
        nonLiveSource: EntitlementSnapshot.Source
    ) throws -> EntitlementSnapshot {
        try RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
                requestDate: Date().addingTimeInterval(-age)
            ),
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil,
            nonLiveSource: nonLiveSource
        )
    }

    @Test("A just-fetched response is live")
    func freshResponseIsLive() throws {
        let snapshot = try makeSnapshot(requestedAgo: 0, nonLiveSource: .cache)

        #expect(snapshot.isPro)
        #expect(snapshot.source == .live)
    }

    @Test(
        "A cached response keeps its entitlements but takes the caller's non-live label",
        arguments: [EntitlementSnapshot.Source.cache, .cacheSeed]
    )
    func cachedResponseIsNotLive(_ nonLiveSource: EntitlementSnapshot.Source) throws {
        let snapshot = try makeSnapshot(requestedAgo: 3600, nonLiveSource: nonLiveSource)

        #expect(snapshot.isPro)
        #expect(snapshot.source == nonLiveSource)
    }

    @Test("A cached stream replay does not renew ResilientPaywallService's cache")
    func cachedStreamReplayIsNotCached() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let store = InMemoryKeyValueStore()
        let resilient = ResilientPaywallService(
            base: StreamOnlyPaywallService(
                stream: RevenueCatPaywallService.mapStream(
                    upstream,
                    entitlementID: "pro",
                    permanentLicenseEntitlementID: nil
                )
            ),
            store: store
        )
        var iterator = resilient.customerInfoStream().makeAsyncIterator()

        continuation.yield(
            makeCustomerInfo(
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
                requestDate: Date().addingTimeInterval(-3 * 24 * 3600)
            )
        )
        let replay = await iterator.next()

        #expect(replay?.isPro == true)
        #expect(replay?.source == .cacheSeed)
        #expect(store.value(.lastKnownEntitlement) == nil)

        continuation.finish()
    }
}

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

@Suite("RevenueCatPaywallService.restoreStrategy")
struct RestoreStrategyTests {
    // `Purchases.configure` is once-per-process, so the observer-mode branch can't be exercised
    // against the live SDK here; the decision is covered through the pure `restoreStrategy`.
    @Test("Default completion mode restores")
    func revenueCatModeRestores() {
        #expect(RevenueCatPaywallService.restoreStrategy(for: .revenueCat) == .restore)
    }

    @Test("Observer mode syncs")
    func myAppModeSyncs() {
        #expect(RevenueCatPaywallService.restoreStrategy(for: .myApp) == .sync)
    }
}

@Suite("RevenueCatPaywallService.mapStream")
struct MapStreamTests {
    @Test("Upstream values map through to snapshot stream")
    func upstreamValuesMap() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        var iterator = mapped.makeAsyncIterator()

        continuation.yield(makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]))
        let first = await iterator.next()
        #expect(first?.isPro == true)

        continuation.yield(makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: false)]))
        let second = await iterator.next()
        #expect(second?.isPro == false)

        continuation.finish()
    }

    @Test("Permanent-license identifier surfaces hasPermanentLicense")
    func permanentLicenseSurfaces() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: "lifetime"
        )

        var iterator = mapped.makeAsyncIterator()

        continuation.yield(
            makeCustomerInfo(
                entitlements: [
                    "lifetime": makeEntitlement(id: "lifetime", isActive: true)
                ]
            )
        )
        let snap = await iterator.next()
        #expect(snap?.isPro == false)
        #expect(snap?.hasPermanentLicense == true)

        continuation.finish()
    }

    @Test("Upstream finish terminates the mapped stream")
    func upstreamFinishTerminates() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        var iterator = mapped.makeAsyncIterator()

        continuation.yield(makeCustomerInfo(entitlements: [:]))
        _ = await iterator.next()
        continuation.finish()

        let terminal = await iterator.next()
        #expect(terminal == nil)
    }

    @Test("A slow consumer sees the newest snapshot, not a stale backlog")
    func slowConsumerSeesNewest() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        var iterator = mapped.makeAsyncIterator()

        // Consume the first value so the mapping task is known to be running, then let two
        // more arrive before the consumer returns: only the newest may survive the buffer.
        continuation.yield(makeCustomerInfo(entitlements: [:]))
        let first = await iterator.next()
        #expect(first?.isPro == false)

        continuation.yield(makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: false)]))
        continuation.yield(makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]))
        continuation.finish()

        var received: [EntitlementSnapshot] = []
        while let snapshot = await iterator.next() {
            received.append(snapshot)
        }
        #expect(received.last?.isPro == true, "The newest snapshot must be delivered.")
    }
}

// MARK: - Helpers

private func makeCustomerInfo(
    entitlements: [String: EntitlementInfo],
    verification: VerificationResult = .notRequested,
    requestDate: Date = Date()
) -> CustomerInfo {
    CustomerInfo(
        entitlements: EntitlementInfos(entitlements: entitlements, verification: verification),
        requestDate: requestDate,
        firstSeen: Date(),
        originalAppUserId: "test-user"
    )
}

private func makeEntitlement(
    id: String,
    isActive: Bool,
    verification: VerificationResult = .notRequested
) -> EntitlementInfo {
    EntitlementInfo(
        identifier: id,
        isActive: isActive,
        willRenew: false,
        periodType: .normal,
        store: .appStore,
        productIdentifier: "\(id).product",
        isSandbox: true,
        ownershipType: .purchased,
        verification: verification
    )
}

/// A base service whose reads map `info` exactly as ``RevenueCatPaywallService`` maps a live
/// `Purchases.shared` result, so a test drives `ResilientPaywallService` through the adapter's real
/// mapping without a configured RevenueCat SDK.
private struct ReadOnlyPaywallService: PaywallService {
    let info: CustomerInfo
    let permanentLicenseEntitlementID: String?

    func customerInfo() async throws -> EntitlementSnapshot {
        try RevenueCatPaywallService.makeSnapshot(
            from: info,
            entitlementID: "pro",
            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
            nonLiveSource: .cache
        )
    }
    func customerInfoStream() -> AsyncStream<EntitlementSnapshot> { AsyncStream { $0.finish() } }
    func restorePurchases() async throws -> EntitlementSnapshot { try await customerInfo() }
}

/// A base service that only streams, so a test drives `ResilientPaywallService` through the
/// adapter's real `mapStream` without a configured RevenueCat SDK.
private struct StreamOnlyPaywallService: PaywallService {
    let stream: AsyncStream<EntitlementSnapshot>

    func customerInfo() async throws -> EntitlementSnapshot { throw TestError() }
    func customerInfoStream() -> AsyncStream<EntitlementSnapshot> { stream }
    func restorePurchases() async throws -> EntitlementSnapshot { throw TestError() }
}
