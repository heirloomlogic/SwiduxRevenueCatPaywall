# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- A RevenueCat response whose entitlement signature verification failed no longer unlocks anything. Under the default `entitlementVerification: .informational`, RevenueCat still parses a tampered response and only marks it `.failed`, and apps never see that flag, so the service used to map a forged active entitlement to `isPro = true` and `ResilientPaywallService` cached it as last-known-good. The service now rejects a `.failed` result (on the response or on a configured entitlement) and logs a `.fault`: `customerInfo()` and `restorePurchases()` throw the new `RevenueCatPaywallError.verificationFailed`, so `ResilientPaywallService` falls back to its last-known-good as for any failed read and never caches the forged response, and the stream skips it. `.verified`, `.verifiedOnDevice`, and `.notRequested` (verification disabled) grant as before; `.disabled` remains the opt-out.
- The README quickstart, Getting Started, and How to Implement the Service backed `ResilientPaywallService` with `UserDefaultsKeyValueStore`, contradicting Swidux's threat model: a plist is user-editable, so a forged cache entry unlocked pro whenever RevenueCat was unreachable. Every snippet now uses `KeychainKeyValueStore(service:)` and links Swidux's Security Posture article.
- Documented a known issue: signing out offline keeps the previous user's entitlement, in `PaywallState` and in the `ResilientPaywallService` cache, because RevenueCat switches users locally but cannot fetch the new user's customer info. `RevenueCatPaywall.logOut()` and How to Implement the Service now describe it and the interim workaround (remove `.lastKnownEntitlement` from the decorator's store after sign-out) until Swidux ships a cache-clear hook.

### Changed

- Customer info RevenueCat serves from its own cache (a `requestDate` more than five minutes from the device clock) is labelled `.cacheSeed` on the stream and `.cache` from `customerInfo()` / `restorePurchases()` instead of `.live`. The entitlements are unchanged, but `ResilientPaywallService` no longer re-stamps its cache as fresh from RevenueCat's launch-time replay, so its `maxCacheAge` bound applies under RevenueCat too.
- Swidux is now required `from: "1.10.0"` (was `from: "1.3.0"`), and the committed `Package.resolved` pins Swidux 1.10.0 (was 1.6.0). The old floor was never built by anyone: CI only ever built the pinned 1.6.0, while consumers resolve the newest 1.x. The floor is now the version CI verifies, and the first with `EntitlementSnapshot.source`, which the service uses to keep untrusted snapshots out of the entitlement cache.

## Feature summary

1.0.0 was tagged on 2026-06-11 and 1.1.0 on 2026-07-03; per-release notes are on [GitHub Releases](https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/releases). This section summarizes the package as it stands on `main`, including changes made since 1.1.0:

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
