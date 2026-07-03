# Mock Service Reference

API reference for `MockRevenueCatPaywallService` — a controllable `PaywallService` conformer for previews and tests that does not touch `Purchases.shared`.

## Overview

`MockRevenueCatPaywallService` tracks a *current* entitlement snapshot the way the real service reflects RevenueCat's state: ``MockRevenueCatPaywallService/send(_:)`` updates it and pushes it through the stream, and `customerInfo()` / `restorePurchases()` return it. ``MockRevenueCatPaywallService/finish()`` tears the stream down, and the ``MockRevenueCatPaywallService/customerInfoError`` / ``MockRevenueCatPaywallService/restoreError`` properties inject failures for testing error paths.

This mock differs from `MockPaywallService` in SwiduxPaywall: that mock's stream finishes after the initial yield, which is fine for static previews but cannot model purchase, refund, or family-share updates as a sequence. This mock keeps the stream live until you tear it down.

For preview and test patterns built on this type, see <doc:HowToPreviewAndTest>.

## Library target

- Product: `SwiduxRevenueCatPaywall`
- Import: `import SwiduxRevenueCatPaywall`

## Types

### ``MockRevenueCatPaywallService``

```swift
public final class MockRevenueCatPaywallService: PaywallService, @unchecked Sendable {
    public init(isPro: Bool = false, hasPermanentLicense: Bool = false)

    public var customerInfoError: Error?
    public var restoreError: Error?

    public func customerInfo() async throws -> EntitlementSnapshot
    public func customerInfoStream() -> AsyncStream<EntitlementSnapshot>
    public func restorePurchases() async throws -> EntitlementSnapshot

    public func send(_ snapshot: EntitlementSnapshot)
    public func finish()
}
```

Reference type. Internal state is guarded by an `NSLock`; `@unchecked Sendable` because the protected mutable state lives behind that lock.

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

Yields the current snapshot, then every value passed to ``MockRevenueCatPaywallService/send(_:)``. The stream stays open until ``MockRevenueCatPaywallService/finish()`` is called.

> Note: Each call to this method replaces the active continuation and finishes the previous stream, so an earlier subscriber's `for await` loop terminates instead of hanging. Only the most recent subscriber receives subsequent ``MockRevenueCatPaywallService/send(_:)`` updates.

#### `restorePurchases() async throws -> EntitlementSnapshot`

Returns the current snapshot, exactly like `customerInfo()`. Throws ``MockRevenueCatPaywallService/restoreError`` instead when it is set.

#### ``MockRevenueCatPaywallService/send(_:)``

```swift
public func send(_ snapshot: EntitlementSnapshot)
```

Makes the snapshot current and pushes it to the active stream subscriber. If no stream is active, the snapshot is still recorded — only the stream delivery is skipped.

Use this to simulate purchase, expiration, or family-share updates during a test.

#### ``MockRevenueCatPaywallService/finish()``

```swift
public func finish()
```

Finishes the active entitlement stream. Iterators terminate cleanly. Subsequent calls to ``MockRevenueCatPaywallService/send(_:)`` still update the current snapshot but are no longer delivered to a stream.

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
