# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `RevenueCatPaywall.recordPurchase(_:)` reports an app-owned StoreKit 2 purchase without exposing RevenueCat to the app target.
- Both `revenueCatPaywall` modifiers accept `RevenueCatPaywallPurchaseLogic` for app-owned StoreKit 2 purchase and restore operations.

### Fixed

- The composed `revenueCatPaywall(state:send:)` modifier closes the paywall after a restore that leaves the user entitled, once RevenueCatUI reports the restore complete. RevenueCatUI dismisses after a purchase but not after a restore, so a restoring user stayed on the paywall — with no way out behind a hard paywall (`displayCloseButton: false`).
- A superseded offering fetch can no longer overwrite the resolution for a newer `offeringIdentifier:`.
- `RevenueCatPaywall.logOut()` returns without contacting RevenueCat when the current user is already anonymous, instead of throwing an error the app could not identify without importing RevenueCat.
- Presenting a paywall with an `offeringIdentifier:` no longer traps when `Purchases` is unconfigured (previews, tests); it defers to `PaywallView`'s own handling.
- The offering-fetch warning logs the SDK error's description as private; RevenueCat embeds request paths, which carry the app user ID.
- `MockRevenueCatPaywallService` streams fan out to every subscriber, like RevenueCat's own stream. Previously each new `customerInfoStream()` call finished the previous one, so a second consumer (a second store, or `ResilientPaywallService` alongside the plugin) silently cut the first off.
- The bundled paywall always supplies RevenueCatUI's required purchase and restore handlers in `.myApp` mode. Missing app purchase logic now produces a configuration error when the user acts instead of a Release-build `fatalError` at presentation.
- `RevenueCatPaywallService.restorePurchases()` uses the user-initiated `restorePurchases()` SDK flow in every completion mode. The previous `.myApp` branch called `syncPurchases()`, which does not refresh the App Store receipt and cannot restore a subscription missing from the device receipt.

### Changed

- The RevenueCat requirement is now `from: "5.90.1"`. Earlier SDKs can deliver a previous user's `CustomerInfo` after an identity change, so `logIn(appUserID:)` could report a paying user as free.
- The Swidux requirement is now `from: "1.6.0"`, the first release with `ResilientPaywallService`, which the documented production wiring uses.
- `configure(apiKey:…)`'s `logLevel:` now defaults to `nil`, leaving the SDK's own default (`.debug` in Debug builds, `.info` in Release) instead of forcing `.info`.
- `configure(apiKey:…)` trims surrounding whitespace from the API key, and asserts in Debug and logs a fault in Release for an empty key or a secret (`sk_`) key.
- A response whose entitlement signature fails verification logs a fault. It still grants access, as RevenueCat's `.informational` mode intends.
- An `offeringIdentifier:` already in RevenueCat's offerings cache renders immediately instead of behind a progress indicator, which now has an accessibility label.
- `RevenueCatPaywall.configure` is main-actor isolated so the `Purchases.isConfigured` check-then-configure is atomic.
- `offeringIdentifier:` is re-resolved when it changes, showing a progress indicator while it reloads.
- The macOS customer-center hand-off defers its binding write to a main-actor task, avoiding state mutation during a view update.
- `MockRevenueCatPaywallService` is checked `Sendable`, backed by a `Mutex` instead of `NSLock` plus `@unchecked Sendable`. `finish()` ends the streams open at the time of the call; streams requested afterwards are live.

### Documentation

- `purchasesAreCompletedBy: .myApp` now documents the bundled StoreKit 2 purchase and restore wiring, the reporting-before-finishing order, and the limits of background purchase synchronization.
- Setup guides dispatch `.refreshCustomerInfo` alongside `.observeCustomerInfo`: a new entitlement stream stays silent until RevenueCat delivers customer info, which it may skip at launch when its cache is fresh.
- The store-driven test examples in *How to Preview and Test* are `@MainActor` and wait with a bounded poll; as written they did not compile, and a single `Task.yield()` let them fail intermittently.
- Corrected the entitlement-verification default (`.informational` is the SDK default), the restore rationale, and the claims that the manual modifier wiring is equivalent to the composed modifier.

## [1.1.0] - 2026-07-03

### Added

- `RevenueCatPaywall.logIn(appUserID:)` / `logOut()` — identity switching for authenticated apps without importing RevenueCat in the app target.
- `offeringIdentifier:` on the paywall modifiers, for presenting a specific offering (win-back, regional) with a fallback to the current offering.
- Mutual exclusion between the paywall and customer-center surfaces in the composed modifier (the paywall wins).
- `MockRevenueCatPaywallService` tracks a current snapshot: `send(_:)` updates what `customerInfo()` / `restorePurchases()` return and what new streams yield first. `customerInfoError` / `restoreError` inject failures.

### Changed

- `customerInfoStream()` buffers only the newest snapshot.
- `RevenueCatPaywallService.init` preconditions on `RevenueCatPaywall.configure` having run, so a missing configure fails fast with a named fix.
- Signed entitlement verification defaults to `.informational`; the log level applies before the SDK configures so boot diagnostics are captured.

## [1.0.0] - 2026-06-11

Initial release.

- `RevenueCatPaywallService` — `PaywallService` conformer backed by `Purchases.shared`, mapping `CustomerInfo` to `EntitlementSnapshot` (pro + optional permanent-license entitlements) with a live `customerInfoStream()`.
- `RevenueCatPaywall.configure(apiKey:...)` — package-level SDK configuration so app targets never import RevenueCat, with mirrored `LogLevel`, `EntitlementVerification`, `PurchasesCompletedBy`, and `StoreKitVersion` options.
- `MockRevenueCatPaywallService` — controllable mock for previews and tests; its stream stays live across `send(_:)` updates and finishes a replaced subscriber instead of stranding it.
- `SwiduxRevenueCatPaywallUI` — `revenueCatPaywall` and `revenueCatCustomerCenter` view modifiers with platform-aware presentation (iOS `fullScreenCover`, sized macOS `sheet`, App Store hand-off for subscription management on macOS) and a `displayCloseButton:` escape hatch that defaults to dismissable.

[Unreleased]: https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/compare/1.1.0...HEAD
[1.1.0]: https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/releases/tag/1.0.0
