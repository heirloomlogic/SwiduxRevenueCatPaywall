//
//  RevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

// Mapping tests use `makeSnapshot` because configuring the real SDK is reserved for the single end-to-end test in RevenueCatPaywallConfigurationTests.
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

    @Test("A failed signature verification still grants access (informational mode)")
    func failedVerificationStillGrants() {
        let info = CustomerInfo(
            entitlements: EntitlementInfos(
                entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
                verification: .failed
            ),
            requestDate: Date(),
            firstSeen: Date(),
            originalAppUserId: "test-user"
        )
        let snapshot = RevenueCatPaywallService.makeSnapshot(
            from: info,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )

        #expect(snapshot.isPro, "Informational verification must never lock users out.")
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
