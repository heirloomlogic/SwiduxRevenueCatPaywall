# Mock Service Reference

API reference for `MockRevenueCatPaywallService` — a controllable `PaywallService` conformer for previews and tests that does not touch `Purchases.shared`.

## Overview

`MockRevenueCatPaywallService` tracks a *current* entitlement snapshot, the way the real service reflects RevenueCat's state: ``MockRevenueCatPaywallService/send(_:)`` updates it and delivers it to every open stream, and `customerInfo()` / `restorePurchases()` return it. Streams fan out: each `customerInfoStream()` call returns an independent stream, so two stores sharing one mock, or a `ResilientPaywallService` wrapper plus the paywall plugin, all see the same transitions. ``MockRevenueCatPaywallService/finish()`` ends the streams that are open at the time, and the ``MockRevenueCatPaywallService/customerInfoError`` / ``MockRevenueCatPaywallService/restoreError`` properties inject failures for testing error paths.

The mock departs from the real `RevenueCatPaywallService` in two deliberate ways, both for deterministic tests:

- A stream buffers every value its consumer has not read yet. The real stream keeps only the newest, so a slow consumer skips intermediate states; with the mock, a test that sends several snapshots before its consumer runs sees each one, in order.
- A new stream always yields the current snapshot first. The real stream yields a first value only if RevenueCat has already delivered customer info in this process, and otherwise stays silent until the next change.

This mock also differs from `MockPaywallService` in SwiduxPaywall: that mock's stream finishes after the initial yield, which is fine for static previews but cannot model purchase, refund, or family-share updates as a sequence.

For vendor-free previews and development builds, Swidux's `SimulatedPaywallService` (in `SwiduxPaywall`) is often the better fit: it is driven from the dev paywall UI in `SwiduxDevPaywallUI`, can simulate latency, and needs no RevenueCat dependency. Prefer this mock in tests that need a synchronous `send(_:)`, arbitrary injected errors, `finish()`, or delivery of repeated identical snapshots (`SimulatedPaywallService` drops a change equal to the current state).

For preview and test patterns built on this type, see <doc:HowToPreviewAndTest>.

## Library target

- Product: `SwiduxRevenueCatPaywall`
- Import: `import SwiduxRevenueCatPaywall`

## Types

### ``MockRevenueCatPaywallService``

```swift
public final class MockRevenueCatPaywallService: PaywallService, Sendable {
    public init(isPro: Bool = false, hasPermanentLicense: Bool = false)

    public var customerInfoError: (any Error)?
    public var restoreError: (any Error)?

    public func customerInfo() async throws -> EntitlementSnapshot
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot>
    public func restorePurchases() async throws -> EntitlementSnapshot

    public func send(_ snapshot: EntitlementSnapshot)
    public func finish()
}
```

Reference type. Internal state lives behind a `Synchronization.Mutex`, so the type is checked `Sendable` and can be shared across actors and tasks.

#### Initializer

```swift
public init(isPro: Bool = false, hasPermanentLicense: Bool = false)
```

- `isPro` — Initial value for `EntitlementSnapshot.isPro`.
- `hasPermanentLicense` — Initial value for `EntitlementSnapshot.hasPermanentLicense`.

The values supplied here become the starting *current* snapshot — what `customerInfo()` / `restorePurchases()` return and what `customerInfoStream()` yields first, until ``MockRevenueCatPaywallService/send(_:)`` replaces it.

#### `customerInfoError` / `restoreError`

Optional errors thrown by `customerInfo()` and `restorePurchases()` respectively while set (`nil`, the default, means success). Set them to drive the plugin's `.refreshFailed` path, retry affordances, or `ResilientPaywallService`'s last-known-good fallback; clear them to restore success.

#### `customerInfo() async throws -> EntitlementSnapshot`

Returns the current snapshot — the init-time state, or the latest value passed to ``MockRevenueCatPaywallService/send(_:)``. This matches the real service: the plugin's dismiss-triggered refresh sees the same state the stream delivered, so a simulated purchase does not regress to free on refresh. Throws ``MockRevenueCatPaywallService/customerInfoError`` instead when it is set.

#### `customerInfoStream() -> AsyncStream<EntitlementSnapshot>`

Returns a new stream that yields the current snapshot, then every value passed to ``MockRevenueCatPaywallService/send(_:)``. Each call returns an independent stream, and every open stream receives every `send(_:)`. A stream stays open until ``MockRevenueCatPaywallService/finish()`` is called while it is open, or until its consumer cancels or drops it; cancelling one stream does not affect the others.

The stream uses unbounded buffering on purpose, so a test observes every transition in order even when it sends faster than its consumer reads. The real service buffers only the newest value.

#### `restorePurchases() async throws -> EntitlementSnapshot`

Returns the current snapshot, exactly like `customerInfo()`. Throws ``MockRevenueCatPaywallService/restoreError`` instead when it is set.

#### ``MockRevenueCatPaywallService/send(_:)``

```swift
public func send(_ snapshot: EntitlementSnapshot)
```

Makes the snapshot current and delivers it to every open stream. With no open stream, the snapshot is still recorded, and the next stream yields it first. Identical consecutive snapshots are each delivered.

Use this to simulate purchase, expiration, or family-share updates during a test.

#### ``MockRevenueCatPaywallService/finish()``

```swift
public func finish()
```

Finishes every stream that is open when called. Consumers receive any values still buffered, then their iterators return `nil`. The mock stays usable: ``MockRevenueCatPaywallService/send(_:)`` keeps updating the current snapshot, and a stream requested afterwards is a fresh, live stream that yields the current snapshot and later sends.

Call this in test teardown or when a preview is done observing entitlement transitions.

## Lifecycle example

```swift
let mock = MockRevenueCatPaywallService(isPro: false)
let stream = mock.customerInfoStream()

var iterator = stream.makeAsyncIterator()
let initial = await iterator.next()  // EntitlementSnapshot(isPro: false, ...)

mock.send(EntitlementSnapshot(isPro: true))
let updated = await iterator.next()  // EntitlementSnapshot(isPro: true, ...)

mock.finish()
let terminal = await iterator.next()  // nil — stream finished

let refreshed = try await mock.customerInfo()  // EntitlementSnapshot(isPro: true, ...) — send(_:) updated it
```

## See Also

- <doc:HowToPreviewAndTest>
- <doc:ServiceReference>
- ``MockRevenueCatPaywallService``
