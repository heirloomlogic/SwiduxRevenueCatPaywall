# Mock Service Reference

API reference for `MockRevenueCatPaywallService` — a controllable `PaywallService` conformer for previews and tests that does not touch `Purchases.shared`.

## Overview

`MockRevenueCatPaywallService` returns a configured snapshot from `customerInfo()` and `restorePurchases()`, and exposes a streaming continuation through ``MockRevenueCatPaywallService/send(_:)`` and ``MockRevenueCatPaywallService/finish()`` so tests can simulate entitlement transitions over time.

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

The values supplied here become the initial snapshot returned by `customerInfo()` / `restorePurchases()` and the first value yielded by `customerInfoStream()`.

#### `customerInfo() async throws -> EntitlementSnapshot`

Returns the snapshot supplied at init. Updates pushed via ``MockRevenueCatPaywallService/send(_:)`` do **not** change the value returned here. Use this method when a test needs a one-shot fetch independent of the stream.

#### `customerInfoStream() -> AsyncStream<EntitlementSnapshot>`

Yields the initial snapshot, then every value passed to ``MockRevenueCatPaywallService/send(_:)``. The stream stays open until ``MockRevenueCatPaywallService/finish()`` is called.

> Note: Each call to this method replaces the active continuation and finishes the previous stream, so an earlier subscriber's `for await` loop terminates instead of hanging. Only the most recent subscriber receives subsequent ``MockRevenueCatPaywallService/send(_:)`` updates.

#### `restorePurchases() async throws -> EntitlementSnapshot`

Returns the snapshot supplied at init. Independent of the stream.

#### ``MockRevenueCatPaywallService/send(_:)``

```swift
public func send(_ snapshot: EntitlementSnapshot)
```

Pushes a snapshot to the active stream subscriber. No-op if no stream has been requested yet, or if the active stream has been finished.

Use this to simulate purchase, expiration, or family-share updates during a test.

#### ``MockRevenueCatPaywallService/finish()``

```swift
public func finish()
```

Finishes the active entitlement stream. Iterators terminate cleanly. Subsequent calls to ``MockRevenueCatPaywallService/send(_:)`` are no-ops.

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
```

## See Also

- <doc:HowToPreviewAndTest>
- <doc:ServiceReference>
- ``MockRevenueCatPaywallService``
