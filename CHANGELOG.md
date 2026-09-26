# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The composed `revenueCatPaywall(state:send:)` modifier dispatches `.dismiss` when `PaywallState.isGateSatisfied` turns `true` while the paywall is up. RevenueCatUI dismisses after a purchase but not after a restore, so a restoring user stayed on the paywall — with no way out behind a hard paywall (`displayCloseButton: false`).
- `RevenueCatPaywallService.customerInfoStream()` drops consecutive equal snapshots. RevenueCat re-emits on every refetch, and each redundant update superseded any in-flight refresh or restore in the Swidux paywall plugin, discarding its result.
- `RevenueCatPaywall.logOut()` returns without contacting RevenueCat when the current user is already anonymous, instead of throwing an error the app could not identify without importing RevenueCat.
- Presenting a paywall with an `offeringIdentifier:` no longer traps when `Purchases` is unconfigured (previews, tests); it defers to `PaywallView`'s own handling.
- The offering-fetch warning logs the SDK error's description as private; RevenueCat embeds request paths, which carry the app user ID.

### Changed

- The RevenueCat requirement is now `from: "5.90.1"`. Earlier SDKs can deliver a previous user's `CustomerInfo` after an identity change, so `logIn(appUserID:)` could report a paying user as free.
- The Swidux requirement is now `from: "1.6.0"`, the first release with `ResilientPaywallService`, which the documented production wiring uses.
- `configure(apiKey:…)`'s `logLevel:` now defaults to `nil`, leaving the SDK's own default (`.debug` in Debug builds, `.info` in Release) instead of forcing `.info`.
- `configure(apiKey:…)` asserts in Debug and logs a fault in Release for an empty API key or a secret (`sk_`) key.
- A response whose entitlement signature fails verification logs a fault. It still grants access, as RevenueCat's `.informational` mode intends.
- An `offeringIdentifier:` already in RevenueCat's offerings cache renders immediately instead of behind a progress indicator, which now has an accessibility label.
- `restorePurchases()` reads the SDK's `purchasesAreCompletedBy` mode live and calls `syncPurchases()` in observer mode (`.myApp`), `restorePurchases()` otherwise.
- `RevenueCatPaywall.configure` is main-actor isolated so the `Purchases.isConfigured` check-then-configure is atomic.
- `offeringIdentifier:` is re-resolved when it changes, showing a progress indicator while it reloads.
- The macOS customer-center hand-off defers its binding write to a main-actor task, avoiding state mutation during a view update.

### Documentation

- `purchasesAreCompletedBy: .myApp` documents that the bundled paywall UI does not support it yet.
- Setup guides dispatch `.refreshCustomerInfo` alongside `.observeCustomerInfo`: RevenueCat replays its latest customer info only to observers attached when it arrived.
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
