//
//  RevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

@Suite("RevenueCatPaywallService")
struct RevenueCatPaywallServiceTests {
    @Test("Active pro entitlement maps to isPro=true")
    func activeProMapsToIsPro() {
        let service = RevenueCatPaywallService(entitlementID: "pro")
        let info = makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)])

        let snapshot = service.snapshot(from: info)

        #expect(snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Inactive pro entitlement maps to isPro=false")
    func inactiveProMapsToFalse() {
        let service = RevenueCatPaywallService(entitlementID: "pro")
        let info = makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: false)])

        let snapshot = service.snapshot(from: info)

        #expect(!snapshot.isPro)
    }

    @Test("Missing pro entitlement maps to isPro=false")
    func missingProMapsToFalse() {
        let service = RevenueCatPaywallService(entitlementID: "pro")
        let info = makeCustomerInfo(entitlements: [:])

        let snapshot = service.snapshot(from: info)

        #expect(!snapshot.isPro)
        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Active permanent-license entitlement sets hasPermanentLicense=true")
    func activeLifetimeMapsToPermanentLicense() {
        let service = RevenueCatPaywallService(entitlementID: "pro", permanentLicenseEntitlementID: "lifetime")
        let info = makeCustomerInfo(entitlements: [
            "lifetime": makeEntitlement(id: "lifetime", isActive: true)
        ])

        let snapshot = service.snapshot(from: info)

        #expect(!snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }

    @Test("Lifetime entitlement is ignored when no permanent-license ID is configured")
    func lifetimeIgnoredWhenNoIDConfigured() {
        let service = RevenueCatPaywallService(entitlementID: "pro")
        let info = makeCustomerInfo(entitlements: [
            "lifetime": makeEntitlement(id: "lifetime", isActive: true)
        ])

        let snapshot = service.snapshot(from: info)

        #expect(!snapshot.hasPermanentLicense)
    }

    @Test("Both pro and lifetime active sets both flags")
    func bothActiveSetsBothFlags() {
        let service = RevenueCatPaywallService(entitlementID: "pro", permanentLicenseEntitlementID: "lifetime")
        let info = makeCustomerInfo(entitlements: [
            "pro": makeEntitlement(id: "pro", isActive: true),
            "lifetime": makeEntitlement(id: "lifetime", isActive: true),
        ])

        let snapshot = service.snapshot(from: info)

        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }

    @Test("Inactive permanent-license entitlement keeps hasPermanentLicense=false")
    func inactiveLifetimeKeepsFalse() {
        let service = RevenueCatPaywallService(entitlementID: "pro", permanentLicenseEntitlementID: "lifetime")
        let info = makeCustomerInfo(entitlements: [
            "lifetime": makeEntitlement(id: "lifetime", isActive: false)
        ])

        let snapshot = service.snapshot(from: info)

        #expect(!snapshot.hasPermanentLicense)
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

    @Test("Restore returns configured snapshot")
    func restoreReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true, hasPermanentLicense: true)
        let snapshot = try await mock.restorePurchases()
        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
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
