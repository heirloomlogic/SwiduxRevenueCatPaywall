//
//  ResolvedOfferingResolutionTests.swift
//  SwiduxRevenueCatPaywallUITests
//

import Foundation
import RevenueCat
import Testing

@testable import SwiduxRevenueCatPaywallUI

/// Sentinel error the fetch-failure case throws so the test asserts on the fallback, not the type.
private struct SomeTestError: Error {}

private func makeOffering(identifier: String) -> Offering {
    Offering(
        identifier: identifier,
        serverDescription: "test offering",
        availablePackages: [],
        webCheckoutUrl: nil
    )
}

@Suite("ResolvedOfferingPaywallView.resolution")
struct ResolvedOfferingResolutionTests {
    @Test("A fetched offering resolves to .resolved carrying that offering")
    func fetchedOfferingResolves() {
        let offering = makeOffering(identifier: "winback")
        let resolution = ResolvedOfferingPaywallView.resolution(
            from: .success(offering),
            identifier: "winback"
        )

        guard case .resolved(let resolved) = resolution else {
            Issue.record("Expected .resolved, got \(resolution)")
            return
        }
        #expect(resolved.identifier == "winback")
    }

    @Test("A missing offering falls back to the current offering")
    func missingOfferingFallsBack() {
        let resolution = ResolvedOfferingPaywallView.resolution(
            from: .success(nil),
            identifier: "missing"
        )

        guard case .currentOffering = resolution else {
            Issue.record("Expected .currentOffering, got \(resolution)")
            return
        }
    }

    @Test("A failed fetch falls back to the current offering")
    func failedFetchFallsBack() {
        let resolution = ResolvedOfferingPaywallView.resolution(
            from: .failure(SomeTestError()),
            identifier: "regional"
        )

        guard case .currentOffering = resolution else {
            Issue.record("Expected .currentOffering, got \(resolution)")
            return
        }
    }
}
