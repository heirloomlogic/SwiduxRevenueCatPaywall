//
//  IdentityFenceTests.swift
//  SwiduxRevenueCatPaywallTests
//

import Foundation
import RevenueCat
import Swidux
import SwiduxPaywall
import Synchronization
import Testing

@testable import SwiduxRevenueCatPaywall

// Account A has pro; account B and the anonymous user do not. Every scenario delivers A's pro
// entitlement late and checks that it never reaches the identity that replaced A. Each test uses
// its own identity gate so identity operations in parallel suites cannot change the outcome.
@Suite("RevenueCatPaywallService identity fence", .timeLimit(.minutes(1)))
@MainActor
struct IdentityFenceTests {
    enum Transition: CaseIterable, CustomTestStringConvertible {
        case logInToB
        case logOutToAnonymous
        case offlineLogOutThatThrows
        case directRevenueCatSwitch

        var testDescription: String {
            switch self {
            case .logInToB: "A-to-B login"
            case .logOutToAnonymous: "logout to anonymous"
            case .offlineLogOutThatThrows: "offline logout that throws after the identity changed"
            case .directRevenueCatSwitch: "identity change made directly through RevenueCat"
            }
        }

        func perform(service: RevenueCatPaywallService, user: AppUserID) async {
            switch self {
            case .logInToB:
                let result = try? await service.logIn(
                    currentIdentity: { user.identity },
                    operation: {
                        user.set("B")
                        return freeInfo()
                    }
                )
                #expect(result?.identity == .appUserID("B"))
            case .logOutToAnonymous:
                let result = try? await service.logOut(
                    currentIdentity: { user.identity },
                    cachedCustomerInfo: { nil },
                    operation: {
                        user.set(anonymousID)
                        return freeInfo()
                    }
                )
                #expect(result?.identity == .anonymous)
            case .offlineLogOutThatThrows:
                do {
                    _ = try await service.logOut(
                        currentIdentity: { user.identity },
                        cachedCustomerInfo: { nil },
                        operation: {
                            user.set(anonymousID)
                            throw NSError(
                                domain: ErrorCode.errorDomain,
                                code: ErrorCode.offlineConnectionError.rawValue
                            )
                        }
                    )
                    Issue.record("Expected the offline logout to throw")
                } catch {
                    #expect(error.identityChanged)
                    #expect(error.identityAfter == .anonymous)
                }
            case .directRevenueCatSwitch:
                user.set("B")
            }
        }
    }

    private let gate = RevenueCatIdentityOperationGate()

    private var service: RevenueCatPaywallService {
        RevenueCatPaywallService(entitlementID: "pro", permanentLicenseEntitlementID: nil, identityGate: gate)
    }

    // MARK: Reads and restores

    @Test("A read with no identity change is delivered")
    func unchangedReadIsDelivered() async throws {
        let snapshot = try await service.fencedSnapshot(appUserID: { "A" }, fetch: { proInfo() })

        #expect(snapshot.isPro)
    }

    // Reads and restores share `fencedSnapshot`, so this covers both public entry points.
    @Test("A read or restore that resolves after the identity changed is discarded", arguments: Transition.allCases)
    func delayedReadIsDiscarded(_ transition: Transition) async {
        let user = AppUserID("A")
        let service = self.service
        let (fetchStarted, started) = AsyncStream<Void>.makeStream()
        let (releaseFetch, release) = AsyncStream<Void>.makeStream()
        let read = Task {
            try await service.fencedSnapshot(
                appUserID: { user.current },
                fetch: {
                    started.yield(())
                    for await _ in releaseFetch { break }
                    return proInfo()
                }
            )
        }
        for await _ in fetchStarted { break }

        await transition.perform(service: service, user: user)
        release.yield(())

        await #expect(throws: RevenueCatPaywallError.identityChanged) { try await read.value }
    }

    @Test("A read that starts during a login waits and reads the new identity")
    func readDuringLoginWaits() async throws {
        let user = AppUserID("A")
        let service = self.service
        let (loginStarted, started) = AsyncStream<Void>.makeStream()
        let (releaseLogin, release) = AsyncStream<Void>.makeStream()
        let (readAttempted, attempted) = AsyncStream<Void>.makeStream()
        let fetchedFor = Mutex<String?>(nil)
        let login = Task {
            try await service.logIn(
                currentIdentity: { user.identity },
                operation: {
                    started.yield(())
                    for await _ in releaseLogin { break }
                    user.set("B")
                    return freeInfo()
                }
            )
        }
        for await _ in loginStarted { break }
        let read = Task {
            attempted.yield(())
            return try await service.fencedSnapshot(
                appUserID: { user.current },
                fetch: {
                    fetchedFor.withLock { $0 = user.current }
                    return user.current == "A" ? proInfo() : freeInfo()
                }
            )
        }
        for await _ in readAttempted { break }
        #expect(fetchedFor.withLock { $0 } == nil, "The read must not start while the login runs.")

        release.yield(())
        _ = try await login.value
        let snapshot = try await read.value

        #expect(fetchedFor.withLock { $0 } == "B")
        #expect(!snapshot.isPro)
    }

    @Test("ResilientPaywallService retries a discarded read onto the new identity and never caches A")
    func resilientRetriesOntoNewIdentity() async throws {
        let user = AppUserID("A")
        let service = self.service
        let store = InMemoryKeyValueStore()
        let (fetchStarted, started) = AsyncStream<Void>.makeStream()
        let (releaseFetch, release) = AsyncStream<Void>.makeStream()
        let calls = Mutex(0)
        let resilient = ResilientPaywallService(
            base: FencedReadService(service: service, user: user) {
                let call = calls.withLock { calls in
                    calls += 1
                    return calls
                }
                guard call == 1 else { return user.current == "A" ? proInfo() : freeInfo() }
                started.yield(())
                for await _ in releaseFetch { break }
                return proInfo()
            },
            store: store,
            maxAttempts: 2,
            retryBaseDelay: .zero
        )
        let read = Task { try await resilient.customerInfo() }
        for await _ in fetchStarted { break }

        await Transition.logInToB.perform(service: service, user: user)
        release.yield(())
        let snapshot = try await read.value

        #expect(!snapshot.isPro)
        #expect(calls.withLock { $0 } == 2)
        #expect(store.value(.lastKnownEntitlement)?.isPro == false)
    }

    // MARK: Streams

    @Test("A stream value delivered late for A is dropped after the identity changed", arguments: Transition.allCases)
    func delayedStreamValueIsDropped(_ transition: Transition) async throws {
        let user = AppUserID("A")
        let upstreams = Upstreams()
        var subscriptions = upstreams.subscriptions.makeAsyncIterator()
        var snapshots = mapStream(upstreams: upstreams, user: user).makeAsyncIterator()

        let first = try #require(await subscriptions.next())
        let aInfo = proInfo()
        upstreams.send(aInfo, for: "A", through: first)
        #expect(await snapshots.next()?.isPro == true)

        await transition.perform(service: service, user: user)
        first.continuation.yield(aInfo)

        // Ends only once the stale subscription, and anything it buffered, was released.
        for await _ in first.ended {}
        let second = try #require(await subscriptions.next())
        upstreams.send(freeInfo(for: user.current), for: user.current, through: second)
        #expect(await snapshots.next()?.isPro == false)
    }

    // RevenueCat replaces the value it replays only when it delivers new customer info to an
    // observer. An offline logout, or a switch that fetches nothing, leaves A's info in place.
    @Test(
        "A resubscription's replay of A's customer info is dropped after the identity changed",
        arguments: Transition.allCases
    )
    func replayAfterResubscriptionIsDropped(_ transition: Transition) async throws {
        let user = AppUserID("A")
        let upstreams = Upstreams()
        var subscriptions = upstreams.subscriptions.makeAsyncIterator()
        var snapshots = mapStream(upstreams: upstreams, user: user).makeAsyncIterator()

        let first = try #require(await subscriptions.next())
        let aInfo = proInfo()
        upstreams.send(aInfo, for: "A", through: first)
        #expect(await snapshots.next()?.isPro == true)

        await transition.perform(service: service, user: user)
        first.continuation.yield(aInfo)
        for await _ in first.ended {}

        // The second subscription replays A's info. Finishing right behind it makes "dropped"
        // observable as the stream ending with nothing yielded.
        let second = try #require(await subscriptions.next())
        second.continuation.finish()
        #expect(await snapshots.next() == nil, "A's replayed info must not reach the new identity.")
    }

    @Test("A stream started after an offline logout drops the replay of A's customer info")
    func newStreamAfterOfflineLogOutDropsReplay() async throws {
        let user = AppUserID("A")
        let upstreams = Upstreams()
        upstreams.record(proInfo(), for: "A")
        await Transition.offlineLogOutThatThrows.perform(service: service, user: user)

        var subscriptions = upstreams.subscriptions.makeAsyncIterator()
        var snapshots = mapStream(upstreams: upstreams, user: user).makeAsyncIterator()
        let subscription = try #require(await subscriptions.next())
        subscription.continuation.finish()

        #expect(await snapshots.next() == nil, "A's replayed info must not reach the anonymous user.")
    }

    @Test("A replay of the current customer's info is delivered, including under an alias")
    func replayForCurrentCustomerIsDelivered() async throws {
        let user = AppUserID("B")
        let upstreams = Upstreams()
        // B's RevenueCat customer began as an anonymous user, so its original ID is not "B".
        upstreams.record(proInfo(for: "$RCAnonymousID:original"), for: "B")

        var subscriptions = upstreams.subscriptions.makeAsyncIterator()
        var snapshots = mapStream(upstreams: upstreams, user: user).makeAsyncIterator()
        let subscription = try #require(await subscriptions.next())
        subscription.continuation.finish()

        #expect(await snapshots.next()?.isPro == true)
    }

    @Test("A stream value that arrives during a login is dropped and the stream resumes after it")
    func streamValueDuringLoginIsDropped() async throws {
        let user = AppUserID("A")
        let upstreams = Upstreams()
        var subscriptions = upstreams.subscriptions.makeAsyncIterator()
        var snapshots = mapStream(upstreams: upstreams, user: user).makeAsyncIterator()
        let first = try #require(await subscriptions.next())

        _ = try await service.logIn(
            currentIdentity: { user.identity },
            operation: {
                upstreams.send(proInfo(), for: "A", through: first)
                for await _ in first.ended {}
                user.set("B")
                return freeInfo()
            }
        )

        let second = try #require(await subscriptions.next())
        upstreams.send(freeInfo(for: "B"), for: "B", through: second)
        #expect(await snapshots.next()?.isPro == false)
    }

    private func mapStream(upstreams: Upstreams, user: AppUserID) -> AsyncStream<EntitlementSnapshot> {
        RevenueCatPaywallService.mapStream(
            subscribe: upstreams.subscribe,
            appUserID: { user.current },
            cachedCustomerInfo: { upstreams.cachedCustomerInfo(for: user.current) },
            identityGate: gate,
            entitlementID: "pro",
            permanentLicenseEntitlementID: nil
        )
    }
}

// MARK: - Helpers

private let anonymousID = "$RCAnonymousID:test"

/// Customer info for the RevenueCat customer whose original app user ID is `customer`.
private func proInfo(for customer: String = "A") -> CustomerInfo {
    makeCustomerInfo(
        entitlements: ["pro": makeEntitlement(id: "pro", isActive: true)],
        originalAppUserId: customer
    )
}

private func freeInfo(for customer: String = "test-user") -> CustomerInfo {
    makeCustomerInfo(entitlements: [:], originalAppUserId: customer)
}

/// The app user ID RevenueCat reports, shared with the `@Sendable` closures under test.
final class AppUserID: Sendable {
    private let value: Mutex<String>

    init(_ value: String) {
        self.value = Mutex(value)
    }

    var current: String { value.withLock { $0 } }

    var identity: RevenueCatPaywallIdentity {
        current == anonymousID ? .anonymous : .appUserID(current)
    }

    func set(_ newValue: String) {
        value.withLock { $0 = newValue }
    }
}

/// Stands in for `Purchases.shared.customerInfoStream` and RevenueCat's per-user customer info
/// cache. Every subscription is a new stream whose continuation, and a signal for its
/// termination, is published to the test. Like RevenueCat, a new subscription first replays the
/// customer info last sent, which an identity change does not clear.
private final class Upstreams: Sendable {
    struct Subscription: Sendable {
        let continuation: AsyncStream<CustomerInfo>.Continuation
        let ended: AsyncStream<Void>
    }

    let subscriptions: AsyncStream<Subscription>
    private let publish: AsyncStream<Subscription>.Continuation
    private let lastSent = Mutex<CustomerInfo?>(nil)
    private let cache = Mutex<[String: CustomerInfo]>([:])

    init() {
        (subscriptions, publish) = AsyncStream<Subscription>.makeStream()
    }

    @Sendable func subscribe() -> AsyncStream<CustomerInfo> {
        let (stream, continuation) = AsyncStream<CustomerInfo>.makeStream()
        if let replay = lastSent.withLock({ $0 }) {
            continuation.yield(replay)
        }
        let (ended, endedContinuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { _ in endedContinuation.finish() }
        publish.yield(Subscription(continuation: continuation, ended: ended))
        return stream
    }

    /// Caches `info` for `appUserID` and makes it the value the next subscription replays.
    func record(_ info: CustomerInfo, for appUserID: String) {
        cache.withLock { $0[appUserID] = info }
        lastSent.withLock { $0 = info }
    }

    /// Records `info`, then delivers it through `subscription`.
    func send(_ info: CustomerInfo, for appUserID: String, through subscription: Subscription) {
        record(info, for: appUserID)
        subscription.continuation.yield(info)
    }

    func cachedCustomerInfo(for appUserID: String) -> CustomerInfo? {
        cache.withLock { $0[appUserID] }
    }
}

/// Routes `customerInfo()` through the adapter's fenced read so `ResilientPaywallService` sees the
/// same results it would from a configured RevenueCat SDK.
private struct FencedReadService: PaywallService {
    let service: RevenueCatPaywallService
    let user: AppUserID
    let fetch: @Sendable () async throws -> CustomerInfo

    func customerInfo() async throws -> EntitlementSnapshot {
        try await service.fencedSnapshot(appUserID: { user.current }, fetch: fetch)
    }
    func customerInfoStream() -> AsyncStream<EntitlementSnapshot> { AsyncStream { $0.finish() } }
    func restorePurchases() async throws -> EntitlementSnapshot { try await customerInfo() }
}
