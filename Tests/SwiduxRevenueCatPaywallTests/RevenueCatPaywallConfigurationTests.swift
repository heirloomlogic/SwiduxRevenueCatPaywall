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

@Suite("RevenueCatPaywall.configure", .serialized)
struct RevenueCatPaywallConfigureTests {
    /// `Purchases.isConfigured` is process-wide state with no public deconfigure path. This test
    /// runs the full configure / repeat-configure sequence in a single test body so it doesn't
    /// depend on cross-test ordering.
    @Test("Configures Purchases once, forwards apiKey/appUserID/logLevel, and ignores repeat calls")
    func configuresOnceAndIgnoresRepeats() {
        #expect(!Purchases.isConfigured, "Test must run before any other configure call in the process.")

        RevenueCatPaywall.configure(
            apiKey: "test_api_key",
            appUserID: "test_user",
            logLevel: .debug
        )

        #expect(Purchases.isConfigured)
        #expect(Purchases.shared.appUserID == "test_user")
        #expect(Purchases.logLevel == .debug)

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
