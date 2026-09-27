# Security Policy

## Supported versions

Only the latest tagged release (and `main`) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub's private vulnerability reporting](https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/security/advisories/new)
rather than opening a public issue.

You should receive an acknowledgement within a week. Once a fix is available, the advisory
will be published and credited unless you prefer otherwise.

## Scope notes

- The `apiKey` accepted by `RevenueCatPaywall.configure` is RevenueCat's *public* SDK key; it is not a secret. Entitlement trust comes from RevenueCat's server — signed entitlement verification (`entitlementVerification: .informational`) is on by default, and `RevenueCatPaywallService` rejects a response that fails verification (reads throw `RevenueCatPaywallError.verificationFailed`, so a `ResilientPaywallService` cache serves its last-known-good; the stream skips it), so a response rewritten in transit — for example by an intercepting proxy whose root certificate the user has trusted — grants nothing.
- This package contains no networking of its own; all network traffic is the RevenueCat
  SDK's. Vulnerabilities in the RevenueCat SDK should be reported to
  [RevenueCat](https://github.com/RevenueCat/purchases-ios/security).
