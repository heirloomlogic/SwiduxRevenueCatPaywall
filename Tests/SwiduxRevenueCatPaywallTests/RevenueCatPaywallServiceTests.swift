//
//  RevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

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
            permanentLicenseEntitlementID: permanentLicenseEntitlementID
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

    @Test("Consecutive equal snapshots are delivered once")
    func consecutiveDuplicatesDropped() async {
        let (upstream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        let mapped = RevenueCatPaywallService.mapStream(
            upstream,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        var iterator = mapped.makeAsyncIterator()

        // Each refetch is a distinct CustomerInfo (fresh request date) mapping to the same
        // snapshot. Awaiting each delivery keeps the newest-only buffer out of the picture.
        continuation.yield(makeCustomerInfo(entitlements: [:]))
        #expect(await iterator.next() == EntitlementSnapshot())

        continuation.yield(makeCustomerInfo(entitlements: [:]))
        continuation.yield(makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]))
        #expect(await iterator.next() == EntitlementSnapshot(isPro: true), "The duplicate must be skipped.")

        continuation.yield(makeCustomerInfo(entitlements: [:]))
        #expect(await iterator.next() == EntitlementSnapshot(), "A later change back must still be delivered.")

        continuation.finish()
        #expect(await iterator.next() == nil)
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

private func makeCustomerInfo(entitlements: [String: EntitlementInfo]) -> CustomerInfo {
    CustomerInfo(
        entitlements: EntitlementInfos(entitlements: entitlements),
        requestDate: Date(),
        firstSeen: Date(),
        originalAppUserId: "test-user"
    )
}

private func makeEntitlement(id: String, isActive: Bool) -> EntitlementInfo {
    EntitlementInfo(
        identifier: id,
        isActive: isActive,
        willRenew: false,
        periodType: .normal,
        store: .appStore,
        productIdentifier: "\(id).product",
        isSandbox: true,
        ownershipType: .purchased
    )
}
