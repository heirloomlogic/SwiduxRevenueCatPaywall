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
    ) -> EntitlementSnapshot {
        RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(entitlements: entitlements),
            entitlementID: entitlementID,
            permanentLicenseEntitlementID: permanentLicenseEntitlementID,
            nonLiveSource: .cache
        )
    }

    @Test("Active pro entitlement maps to isPro=true")
    func activeProMapsToIsPro() {
        let snapshot = makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]
        )

        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Inactive pro entitlement maps to isPro=false")
    func inactiveProMapsToFalse() {
        let snapshot = makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: false)]
        )

        #expect(!snapshot.isPro)
    }

    @Test("Missing pro entitlement maps to isPro=false")
    func missingProMapsToFalse() {
        let snapshot = makeSnapshot(entitlements: [:])

        #expect(!snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Active permanent-license entitlement sets hasPermanentLicense=true")
    func activeLifetimeMapsToPermanentLicense() {
        let snapshot = makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: true)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(!snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }

    @Test("Lifetime entitlement is ignored when no permanent-license ID is configured")
    func lifetimeIgnoredWhenNoIDConfigured() {
        let snapshot = makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: true)]
        )

        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Both pro and lifetime active sets both flags")
    func bothActiveSetsBothFlags() {
        let snapshot = makeSnapshot(
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
    func proActiveLifetimeAbsentSetsOnlyIsPro() {
        let snapshot = makeSnapshot(
            entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Inactive permanent-license entitlement keeps hasPermanentLicense=false")
    func inactiveLifetimeKeepsFalse() {
        let snapshot = makeSnapshot(
            entitlements: ["lifetime": makeEntitlement(id: "lifetime", isActive: false)],
            permanentLicenseEntitlementID: "lifetime"
        )

        #expect(!snapshot.hasPermanentLicense)
    }
}

// A tampered response is exactly what verification exists to catch, and apps never see
// `CustomerInfo` — the adapter is the only place the verification result can be acted on.
@Suite("RevenueCatPaywallService entitlement verification")
struct EntitlementVerificationTests {
    @Test("A response that failed signature verification grants nothing and is not live")
    func failedResponseGrantsNothing() {
        let snapshot = RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(
                entitlements: [
                    "pro": makeEntitlement(id: "pro", isActive: true, verification: .failed),
                    "lifetime": makeEntitlement(id: "lifetime", isActive: true, verification: .failed),
                ],
                verification: .failed
            ),
            entitlementID: "pro",
            permanentLicenseEntitlementID: "lifetime",
            nonLiveSource: .cache
        )

        #expect(!snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
        #expect(snapshot.source != .live, "A forged response must never be offered to a cache as live.")
    }

    @Test("A failed entitlement is not trusted even when the response-level result is not failed")
    func failedEntitlementGrantsNothing() {
        let snapshot = RevenueCatPaywallService.makeSnapshot(
            from: makeCustomerInfo(
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true, verification: .failed)],
                verification: .verified
            ),
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil,
            nonLiveSource: .cache
        )

        #expect(!snapshot.isPro)
        #expect(snapshot.source != .live)
    }

    @Test(
        "Verified, on-device-verified, and unrequested results grant as live",
        arguments: [VerificationResult.verified, .verifiedOnDevice, .notRequested]
    )
    func trustedResultsGrant(_ verification: VerificationResult) {
        let snapshot = RevenueCatPaywallService.makeSnapshot(
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

    @Test("A forged stream value never reaches ResilientPaywallService's cache")
    func forgedStreamValueIsNotCached() async {
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
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true, verification: .failed)],
                verification: .failed
            )
        )
        let snapshot = await iterator.next()

        #expect(snapshot?.isPro == false)
        // The decorator persists before it yields, so the cache is settled by now.
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
    verification: VerificationResult = .notRequested
) -> CustomerInfo {
    CustomerInfo(
        entitlements: EntitlementInfos(entitlements: entitlements, verification: verification),
        requestDate: Date(),
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

/// A base service that only streams, so a test drives `ResilientPaywallService` through the
/// adapter's real `mapStream` without a configured RevenueCat SDK.
private struct StreamOnlyPaywallService: PaywallService {
    let stream: AsyncStream<EntitlementSnapshot>

    func customerInfo() async throws -> EntitlementSnapshot { throw TestError() }
    func customerInfoStream() -> AsyncStream<EntitlementSnapshot> { stream }
    func restorePurchases() async throws -> EntitlementSnapshot { throw TestError() }
}
