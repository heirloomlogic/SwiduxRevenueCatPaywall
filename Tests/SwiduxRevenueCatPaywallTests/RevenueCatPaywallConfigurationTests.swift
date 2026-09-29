//
//  RevenueCatPaywallConfigurationTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import StoreKit
import SwiduxPaywall
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

@Suite("RevenueCatPaywall.storeKitSelection")
struct RevenueCatPaywallStoreKitSelectionTests {
    // `Purchases.configure` is once-per-process, so only one end-to-end configure path can run
    // in this suite. The coupled purchasesAreCompletedBy/storeKitVersion forwarding is therefore
    // covered here at the decision level, through the pure `storeKitSelection` function.
    @Test("Completion override without a pinned version forwards the SDK default (StoreKit 2)")
    func completedByWithoutVersionForwardsDefault() {
        let selection = RevenueCatPaywall.storeKitSelection(
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: nil
        )
        #expect(selection == .completedBy(.myApp, .storeKit2))
    }

    @Test("Completion override with a pinned version forwards both")
    func completedByWithVersionForwardsBoth() {
        let selection = RevenueCatPaywall.storeKitSelection(
            purchasesAreCompletedBy: .revenueCat,
            storeKitVersion: .storeKit1
        )
        #expect(selection == .completedBy(.revenueCat, .storeKit1))
    }

    @Test("A pinned version without a completion override forwards only the version")
    func versionOnlyForwardsVersion() {
        let selection = RevenueCatPaywall.storeKitSelection(
            purchasesAreCompletedBy: nil,
            storeKitVersion: .storeKit1
        )
        #expect(selection == .storeKitVersion(.storeKit1))
    }

    @Test("Neither parameter leaves the builder at SDK defaults")
    func neitherLeavesSDKDefaults() {
        let selection = RevenueCatPaywall.storeKitSelection(
            purchasesAreCompletedBy: nil,
            storeKitVersion: nil
        )
        #expect(selection == .sdkDefault)
    }
}

@Suite("RevenueCatPaywall.apiKeyProblem")
struct RevenueCatPaywallAPIKeyTests {
    @Test("Public SDK keys pass", arguments: ["appl_AbC123", "goog_AbC123", "test_AbC123"])
    func publicKeysPass(key: String) {
        #expect(RevenueCatPaywall.apiKeyProblem(key) == nil)
    }

    @Test("Empty and whitespace-only keys are flagged", arguments: ["", "   ", "\n\t"])
    func emptyKeysFlagged(key: String) {
        #expect(RevenueCatPaywall.apiKeyProblem(key) == .empty)
    }

    @Test("Secret keys are flagged, even with surrounding whitespace", arguments: ["sk_AbC123", " sk_AbC123\n"])
    func secretKeysFlagged(key: String) {
        #expect(RevenueCatPaywall.apiKeyProblem(key) == .secret)
    }
}

@Suite("RevenueCatPaywall.configure", .serialized)
@MainActor
struct RevenueCatPaywallConfigureTests {
    /// `Purchases.isConfigured` is process-wide state with no public deconfigure path. This test
    /// runs the full configure / repeat-configure sequence in a single test body so it doesn't
    /// depend on cross-test ordering.
    ///
    /// The SDK is configured against an ephemeral `UserDefaults` suite (cleared below) so its
    /// cache never lands in the test host's standard defaults. The fake key does trigger
    /// background SDK requests that fail; that network noise is unavoidable without dependency
    /// injection into the SDK, and nothing here awaits those requests.
    @Test("Service calls fail safely before configure and recover after configure")
    func configuresOnceAndIgnoresRepeats() async throws {
        let suiteName = "com.heirloomlogic.SwiduxRevenueCatPaywallTests.configure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!Purchases.isConfigured, "Test must run before any other configure call in the process.")
        let service = RevenueCatPaywallService(entitlementID: "pro")

        await #expect(throws: RevenueCatPaywallError.notConfigured) {
            try await service.customerInfo()
        }
        await #expect(throws: RevenueCatPaywallError.notConfigured) {
            try await service.restorePurchases()
        }
        var earlyIterator = service.customerInfoStream().makeAsyncIterator()
        #expect(await earlyIterator.next() == nil)

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

        let retryResult = await probeFirstResult(of: service.customerInfoStream())
        #expect(retryResult != .finished, "A stream started after configuration must use RevenueCat's live stream.")

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

private enum StreamProbeResult: Equatable {
    case yielded
    case finished
    case remainedOpen
}

private func probeFirstResult(
    of stream: AsyncStream<EntitlementSnapshot>
) async -> StreamProbeResult {
    await withTaskGroup(of: StreamProbeResult.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() == nil ? .finished : .yielded
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(100))
            return .remainedOpen
        }

        let result = await group.next() ?? .finished
        group.cancelAll()
        return result
    }
}

@Suite("RevenueCatPaywallService identity", .serialized)
@MainActor
struct RevenueCatPaywallIdentityTests {
    private let service = RevenueCatPaywallService(entitlementID: "pro")

    @Test("Login returns the new identity and its mapped entitlement snapshot")
    func loginReturnsSnapshot() async throws {
        var identity = RevenueCatPaywallIdentity.anonymous

        let result = try await service.logIn(
            currentIdentity: { identity },
            operation: {
                identity = .appUserID("member")
                return makeCustomerInfo(
                    entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)]
                )
            }
        )

        #expect(result.identity == .appUserID("member"))
        #expect(result.identityChanged)
        #expect(result.snapshot == EntitlementSnapshot(isPro: true))
    }

    @Test("Logout returns the anonymous identity and its mapped entitlement snapshot")
    func logoutReturnsSnapshot() async throws {
        var identity = RevenueCatPaywallIdentity.appUserID("member")

        let result = try await service.logOut(
            currentIdentity: { identity },
            cachedCustomerInfo: { nil },
            operation: {
                identity = .anonymous
                return makeCustomerInfo(entitlements: [:])
            }
        )

        #expect(result.identity == .anonymous)
        #expect(result.identityChanged)
        #expect(result.snapshot == EntitlementSnapshot())
    }

    @Test("Already-anonymous logout skips the SDK operation")
    func anonymousLogoutIsNoOp() async throws {
        var operationCalled = false

        let result = try await service.logOut(
            currentIdentity: { .anonymous },
            cachedCustomerInfo: { nil },
            operation: {
                operationCalled = true
                return makeCustomerInfo(entitlements: [:])
            }
        )

        #expect(!operationCalled)
        #expect(result.identity == .anonymous)
        #expect(!result.identityChanged)
        #expect(result.snapshot == nil)
    }

    @Test("A provider error reports an identity transition that happened before failure")
    func providerFailureReportsTransition() async {
        var identity = RevenueCatPaywallIdentity.appUserID("member")

        do {
            _ = try await service.logOut(
                currentIdentity: { identity },
                cachedCustomerInfo: { nil },
                operation: {
                    identity = .anonymous
                    throw NSError(
                        domain: ErrorCode.errorDomain,
                        code: ErrorCode.offlineConnectionError.rawValue
                    )
                }
            )
            Issue.record("Expected logout to throw")
        } catch {
            #expect(error.operation == .logOut)
            #expect(error.reason == .networkUnavailable)
            #expect(error.identityBefore == .appUserID("member"))
            #expect(error.identityAfter == .anonymous)
            #expect(error.identityChanged)
        }
    }

    @Test("A verification failure reports an identity transition that happened before mapping")
    func verificationFailureReportsTransition() async {
        var identity = RevenueCatPaywallIdentity.anonymous

        do {
            _ = try await service.logIn(
                currentIdentity: { identity },
                operation: {
                    identity = .appUserID("member")
                    return makeCustomerInfo(entitlements: [:], verification: .failed)
                }
            )
            Issue.record("Expected login to throw")
        } catch {
            #expect(error.operation == .logIn)
            #expect(error.reason == .verificationFailed)
            #expect(error.identityBefore == .anonymous)
            #expect(error.identityAfter == .appUserID("member"))
            #expect(error.identityChanged)
        }
    }

    @Test(
        "Overlapping service calls keep each snapshot and failure with its own identity", arguments: [false, true],
        [false, true])
    func overlappingServiceCalls(firstFails: Bool, secondLogsOut: Bool) async throws {
        var identity = RevenueCatPaywallIdentity.anonymous
        let (firstStarted, started) = AsyncStream<Void>.makeStream()
        let (releaseFirst, release) = AsyncStream<Void>.makeStream()
        let (secondStarted, secondAttempted) = AsyncStream<Void>.makeStream()
        var secondEntered = false
        let first = Task { @MainActor in
            try await service.logIn(
                currentIdentity: { identity },
                operation: {
                    identity = .appUserID("first")
                    started.yield(())
                    for await _ in releaseFirst { break }
                    if firstFails {
                        throw NSError(domain: ErrorCode.errorDomain, code: ErrorCode.networkError.rawValue)
                    }
                    return makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)])
                }
            )
        }
        for await _ in firstStarted { break }
        let secondService = RevenueCatPaywallService(entitlementID: "pro")
        let second = Task { @MainActor in
            secondAttempted.yield(())
            if secondLogsOut {
                return try await secondService.logOut(
                    currentIdentity: { identity }, cachedCustomerInfo: { nil },
                    operation: {
                        secondEntered = true
                        identity = .anonymous
                        return makeCustomerInfo(entitlements: [:])
                    }
                )
            }
            return try await secondService.logIn(
                currentIdentity: { identity },
                operation: {
                    secondEntered = true
                    identity = .appUserID("second")
                    return makeCustomerInfo(entitlements: [:])
                }
            )
        }
        for await _ in secondStarted { break }
        #expect(!secondEntered)
        release.yield(())
        do {
            let result = try await first.value
            #expect(!firstFails)
            #expect(result.identity == .appUserID("first"))
            #expect(result.identityChanged)
            #expect(result.snapshot?.isPro == true)
        } catch let error as RevenueCatPaywallIdentityError {
            #expect(firstFails)
            #expect(error.identityBefore == .anonymous)
            #expect(error.identityAfter == .appUserID("first"))
            #expect(error.identityChanged)
        }
        let result = try await second.value
        #expect(result.identity == (secondLogsOut ? .anonymous : .appUserID("second")))
        #expect(result.identityChanged)
        #expect(result.snapshot?.isPro == false)
    }

    @Test(
        "Namespace and service calls share serialization, including failures and anonymous guards",
        arguments: [false, true], [false, true])
    func legacyAndServiceCalls(legacyFirst: Bool, firstFails: Bool) async throws {
        var identity = RevenueCatPaywallIdentity.anonymous
        let (firstStarted, started) = AsyncStream<Void>.makeStream()
        let (releaseFirst, release) = AsyncStream<Void>.makeStream()
        let (secondStarted, secondAttempted) = AsyncStream<Void>.makeStream()
        var secondEntered = false
        let first = Task { @MainActor in
            @MainActor func operation() async throws -> CustomerInfo {
                started.yield(())
                for await _ in releaseFirst { break }
                identity = .appUserID("first")
                if firstFails {
                    throw NSError(domain: ErrorCode.errorDomain, code: ErrorCode.networkError.rawValue)
                }
                return makeCustomerInfo(entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)])
            }
            if legacyFirst {
                try await RevenueCatPaywall.performLegacyIdentityOperation(
                    .logIn, currentIdentity: { identity }, operation: { _ = try await operation() }
                )
            } else {
                let result = try await service.logIn(currentIdentity: { identity }, operation: operation)
                #expect(result.identity == .appUserID("first"))
                #expect(result.snapshot?.isPro == true)
            }
        }
        for await _ in firstStarted { break }
        let second = Task { @MainActor in
            secondAttempted.yield(())
            @MainActor func operation() async throws -> CustomerInfo {
                secondEntered = true
                identity = .anonymous
                return makeCustomerInfo(entitlements: [:])
            }
            if legacyFirst {
                let result = try await service.logOut(
                    currentIdentity: { identity }, cachedCustomerInfo: { nil }, operation: operation
                )
                #expect(result.identity == .anonymous)
                #expect(result.identityChanged)
                #expect(result.snapshot?.isPro == false)
            } else {
                try await RevenueCatPaywall.performLegacyIdentityOperation(
                    .logOut, currentIdentity: { identity }, operation: { _ = try await operation() }
                )
            }
        }
        for await _ in secondStarted { break }
        #expect(!secondEntered)
        release.yield(())
        do {
            try await first.value
            #expect(!firstFails)
        } catch let error as RevenueCatPaywallIdentityError {
            #expect(firstFails)
            #expect(error.identityBefore == .anonymous)
            #expect(error.identityAfter == .appUserID("first"))
            #expect(error.identityChanged)
        }
        try await second.value
        #expect(secondEntered)
        #expect(identity == .anonymous)
    }

    @Test(
        "Anonymous logout maps cached customer info under the configured verification policy",
        arguments: [RevenueCat.VerificationResult.verified, .notRequested, .failed])
    func anonymousLogoutCachedSnapshot(verification: RevenueCat.VerificationResult) async throws {
        let result = try await service.logOut(
            currentIdentity: { .anonymous },
            cachedCustomerInfo: {
                makeCustomerInfo(
                    entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)], verification: verification)
            },
            operation: {
                Issue.record("Already-anonymous logout must not call the SDK")
                return makeCustomerInfo(entitlements: [:])
            }
        )
        #expect(result.identity == .anonymous)
        #expect(!result.identityChanged)
        #expect(result.snapshot?.isPro == (verification == .failed ? nil : true))
    }

    @Test("RevenueCat identity error codes map to package reasons")
    func providerErrorsAreMapped() {
        func reason(_ code: ErrorCode) -> RevenueCatPaywallIdentityError.Reason {
            RevenueCatPaywallService.identityFailureReason(
                from: NSError(domain: ErrorCode.errorDomain, code: code.rawValue)
            )
        }

        #expect(reason(.invalidAppUserIdError) == .invalidAppUserID)
        #expect(reason(.networkError) == .networkUnavailable)
        #expect(reason(.offlineConnectionError) == .networkUnavailable)
        #expect(reason(.signatureVerificationFailed) == .verificationFailed)
        #expect(reason(.configurationError) == .configuration)
        #expect(reason(.unknownError) == .providerFailure)
    }
}

@Suite("RevenueCatPaywall.recordPurchase")
struct RecordPurchaseTests {
    @Test("Forwards the StoreKit result through the package bridge")
    func forwardsPurchaseResult() async throws {
        let recorder = PurchaseResultRecorder()

        try await RevenueCatPaywall.recordPurchase(
            .pending,
            using: { result in
                recorder.record(result)
            }
        )

        #expect(recorder.recordedPending)
    }
}

private final class PurchaseResultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    func record(_ result: Product.PurchaseResult) {
        lock.withLock {
            if case .pending = result { pending = true }
        }
    }

    var recordedPending: Bool {
        lock.withLock { pending }
    }
}
