# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial feature set, pending a first tagged release:

- `RevenueCatPaywallService` — `PaywallService` conformer backed by `Purchases.shared`,
  mapping `CustomerInfo` to `EntitlementSnapshot` (pro + optional permanent-license
  entitlements) with a live `customerInfoStream()`.
- `RevenueCatPaywall.configure(apiKey:...)` — package-level SDK configuration so app targets
  never import RevenueCat, with mirrored `LogLevel`, `EntitlementVerification`,
  `PurchasesCompletedBy`, and `StoreKitVersion` options.
- `MockRevenueCatPaywallService` — controllable mock for previews and tests; its stream stays
  live across `send(_:)` updates and finishes a replaced subscriber instead of stranding it.
- `SwiduxRevenueCatPaywallUI` — `revenueCatPaywall` and `revenueCatCustomerCenter` view
  modifiers with platform-aware presentation (iOS `fullScreenCover`, sized macOS `sheet`,
  App Store hand-off for subscription management on macOS) and a `displayCloseButton:`
  escape hatch that defaults to dismissable.

### Release checklist

- [x] Replace the `branch: "main"` Swidux dependency in `Package.swift` (and the install
      snippets in `README.md` and the DocC guides) with a `from:` version requirement —
      now `from: "1.3.0"`. SwiftPM rejects branch-based dependencies when a package is
      itself resolved by version, so this was a prerequisite for the first tagged release.
