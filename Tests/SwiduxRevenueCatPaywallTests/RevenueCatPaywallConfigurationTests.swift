//
//  RevenueCatPaywallConfigurationTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import Testing

@testable import SwiduxRevenueCatPaywall

@Suite("RevenueCatPaywall.LogLevel mirror")
struct RevenueCatPaywallLogLevelTests {
    @Test(
        "Every mirrored LogLevel case maps to its RevenueCat.LogLevel counterpart",
        arguments: [
            (RevenueCatPaywall.LogLevel.verbose, RevenueCat.LogLevel.verbose),
            (.debug, .debug),
            (.info, .info),
            (.warn, .warn),
            (.error, .error),
        ] as [(RevenueCatPaywall.LogLevel, RevenueCat.LogLevel)]
    )
    func mapsCorrectly(mirror: RevenueCatPaywall.LogLevel, expected: RevenueCat.LogLevel) {
        #expect(mirror.rcValue == expected)
    }
}

// The RevenueCat counterparts of the three mirrors below are public Int enums without a
// Sendable conformance, so they can't ride along as parameterized-test arguments the way
// RevenueCat.LogLevel does above — each mirror is asserted case by case in a single body.

@Suite("RevenueCatPaywall.EntitlementVerification mirror")
struct RevenueCatPaywallEntitlementVerificationTests {
    @Test("Every mirrored case maps to its EntitlementVerificationMode counterpart")
    func mapsCorrectly() {
        #expect(RevenueCatPaywall.EntitlementVerification.disabled.rcValue == .disabled)
        #expect(RevenueCatPaywall.EntitlementVerification.informational.rcValue == .informational)
    }
}

@Suite("RevenueCatPaywall.PurchasesCompletedBy mirror")
struct RevenueCatPaywallPurchasesCompletedByTests {
    @Test("Every mirrored case maps to its PurchasesAreCompletedBy counterpart")
    func mapsCorrectly() {
        #expect(RevenueCatPaywall.PurchasesCompletedBy.revenueCat.rcValue == .revenueCat)
        #expect(RevenueCatPaywall.PurchasesCompletedBy.myApp.rcValue == .myApp)
    }
}

@Suite("RevenueCatPaywall.StoreKitVersion mirror")
struct RevenueCatPaywallStoreKitVersionTests {
    @Test("Every mirrored case maps to its RevenueCat.StoreKitVersion counterpart")
    func mapsCorrectly() {
        #expect(RevenueCatPaywall.StoreKitVersion.storeKit1.rcValue == .storeKit1)
        #expect(RevenueCatPaywall.StoreKitVersion.storeKit2.rcValue == .storeKit2)
    }
}

@Suite("RevenueCatPaywall.configure", .serialized)
struct RevenueCatPaywallConfigureTests {
    /// `Purchases.isConfigured` is process-wide state with no public deconfigure path. This test
    /// runs the full configure / repeat-configure sequence in a single test body so it doesn't
    /// depend on cross-test ordering.
    ///
    /// The SDK is configured against an ephemeral `UserDefaults` suite (cleared below) so its
    /// cache never lands in the test host's standard defaults. The fake key does trigger
    /// background SDK requests that fail; that network noise is unavoidable without dependency
    /// injection into the SDK, and nothing here awaits those requests.
    @Test("Configures Purchases once, forwards parameters, and ignores repeat calls")
    func configuresOnceAndIgnoresRepeats() throws {
        let suiteName = "com.heirloomlogic.SwiduxRevenueCatPaywallTests.configure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!Purchases.isConfigured, "Test must run before any other configure call in the process.")

        RevenueCatPaywall.configure(
            apiKey: "test_api_key",
            appUserID: "test_user",
            userDefaults: defaults,
            logLevel: .debug,
            entitlementVerification: .informational,
            purchasesAreCompletedBy: .myApp
        )

        #expect(Purchases.isConfigured)
        #expect(Purchases.shared.appUserID == "test_user")
        #expect(Purchases.logLevel == .debug)
        #expect(Purchases.shared.purchasesAreCompletedBy == .myApp)

        let firstInstance = ObjectIdentifier(Purchases.shared)

        RevenueCatPaywall.configure(
            apiKey: "different_key",
            appUserID: "different_user",
            logLevel: .error
        )

        #expect(ObjectIdentifier(Purchases.shared) == firstInstance, "Repeat configure must be a no-op.")
        #expect(Purchases.shared.appUserID == "test_user", "appUserID must remain from the first configure.")
        #expect(Purchases.logLevel == .debug, "logLevel must remain from the first configure.")
    }
}
