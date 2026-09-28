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

// Mapping tests use `makeSnapshot` because configuring the real SDK is reserved for the single
// end-to-end test in RevenueCatPaywallConfigurationTests.
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

// Every test here awaits stream values; the time limit turns a regression into a failure
// instead of a CI job hung until its timeout.
@Suite("RevenueCatPaywallService.mapStream", .timeLimit(.minutes(1)))
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

    // `bufferingNewest(1)` itself isn't asserted here: whether an intermediate value is dropped
    // depends on whether the consumer is suspended in `next()` when it arrives, which the test
    // can't control without hooks into the mapping task. This pins the observable contract.
    @Test("A consumer that falls behind still ends on the newest snapshot")
    func slowConsumerSeesNewest() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        var iterator = mapped.makeAsyncIterator()

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

    @Test("Cancelling the consumer terminates the upstream iteration")
    func consumerCancellationPropagates() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let (upstreamEnded, endedContinuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { _ in endedContinuation.finish() }

        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )
        let consumer = Task {
            for await _ in mapped {}
        }

        continuation.yield(makeCustomerInfo(entitlements: [:]))
        consumer.cancel()

        // Completes only once the upstream's onTermination has run.
        for await _ in upstreamEnded {}
        await consumer.value
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
