# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial feature set, pending a first tagged release:

- `RevenueCatPaywallService` — `PaywallService` conformer backed by `Purchases.shared`,
  mapping `CustomerInfo` to `EntitlementSnapshot` (pro + optional permanent-license
  entitlements) with a live `customerInfoStream()`. The stream buffers only the newest
  snapshot, and the initializer preconditions on `RevenueCatPaywall.configure` having run
  (previews and tests use the mock) so a missing configure fails fast with a named fix.
  `restorePurchases()` reads the SDK's `purchasesAreCompletedBy` mode live and calls
  `syncPurchases()` in observer mode (`.myApp`) — where a restore can alias or transfer
  purchases between accounts — and `restorePurchases()` otherwise, so restore dispatches are
  safe in either mode without app-side special-casing.
- `RevenueCatPaywall.configure(apiKey:...)` — package-level SDK configuration so app targets
  never import RevenueCat, with mirrored `LogLevel`, `EntitlementVerification`,
  `PurchasesCompletedBy`, and `StoreKitVersion` options. Signed entitlement verification
  defaults to `.informational`; log verbosity applies before the SDK configures so boot
  diagnostics are captured. Main-actor isolated so the `Purchases.isConfigured`
  check-then-configure is atomic.
- `RevenueCatPaywall.logIn(appUserID:)` / `logOut()` — identity switching for authenticated
  apps without importing RevenueCat in the app target.
- `MockRevenueCatPaywallService` — controllable mock for previews and tests. `send(_:)`
  updates the current snapshot (returned by `customerInfo()` / `restorePurchases()` and
  yielded first by new streams) as well as the live stream, so a plugin refresh after a
  simulated purchase never regresses the gate; `customerInfoError` / `restoreError` inject
  failures; a replaced stream subscriber is finished instead of stranded.
- `SwiduxRevenueCatPaywallUI` — `revenueCatPaywall` and `revenueCatCustomerCenter` view
  modifiers with platform-aware presentation (iOS `fullScreenCover`, sized macOS `sheet`,
  App Store hand-off for subscription management on macOS), an `offeringIdentifier:`
  parameter for presenting a specific offering (win-back, regional) with graceful fallback
  (re-resolved when the identifier changes, showing a progress indicator while it reloads),
  a `displayCloseButton:` escape hatch that defaults to dismissable, and mutual exclusion
  between the two surfaces (the paywall wins) so a refused presentation can never strand
  its state flag.

### Release checklist

- [x] Replace the `branch: "main"` Swidux dependency in `Package.swift` (and the install
      snippets in `README.md` and the DocC guides) with a `from:` version requirement —
      now `from: "1.3.0"`. SwiftPM rejects branch-based dependencies when a package is
      itself resolved by version, so this was a prerequisite for the first tagged release.
- [ ] Tag `1.0.0` as the first release — the install snippets in `README.md` and the DocC
      guides already say `from: "1.0.0"`, so a `0.x` first tag would break every
      copy-pasted requirement. After tagging, update `SECURITY.md`'s "pre-1.0" wording.
