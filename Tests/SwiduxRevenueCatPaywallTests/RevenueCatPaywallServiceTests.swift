//
//  RevenueCatPaywallServiceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import SwiduxPaywall
import Testing

@testable import SwiduxRevenueCatPaywall

@Suite("RevenueCatPaywallService")
struct RevenueCatPaywallServiceTests {
    @Test("Snapshot maps active entitlement to isPro")
    func snapshotMapsPro() {
        let service = RevenueCatPaywallService(entitlementID: "pro")
        #expect(service.entitlementID == "pro")
    }

    @Test("Service initializes with optional permanent license ID")
    func initWithPermanentLicense() {
        let service = RevenueCatPaywallService(
            entitlementID: "pro",
            permanentLicenseEntitlementID: "lifetime"
        )
        #expect(service.permanentLicenseEntitlementID == "lifetime")
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

    @Test("Restore returns configured snapshot")
    func restoreReturnsSnapshot() async throws {
        let mock = MockRevenueCatPaywallService(isPro: true, hasPermanentLicense: true)
        let snapshot = try await mock.restorePurchases()
        #expect(snapshot.isPro)
        #expect(snapshot.hasPermanentLicense)
    }
}
