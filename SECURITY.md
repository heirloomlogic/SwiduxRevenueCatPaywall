# Security Policy

## Supported versions

Only the latest tagged release (and `main`) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately via [GitHub's private vulnerability reporting](https://github.com/HeirloomLogic/SwiduxRevenueCatPaywall/security/advisories/new) rather than opening a public issue.

You should receive an acknowledgement within a week. Once a fix is available, the advisory will be published and credited unless you prefer otherwise.

## Scope notes

- The `apiKey` accepted by `RevenueCatPaywall.configure` is RevenueCat's *public* SDK key; it is not a secret. Passing a secret (`sk_`) key trips an assertion in Debug and logs a fault in Release — such a key must never ship in an app binary.
- Entitlement trust comes from RevenueCat's server. Signed entitlement verification (`.informational`, the SDK default) reports failures, which this adapter rejects: reads and restores throw `RevenueCatPaywallError.verificationFailed` and streams skip the invalid response. Callers that explicitly choose `.disabled` skip verification and trust the response.
- This package contains no networking of its own; all network traffic is the RevenueCat SDK's. Vulnerabilities in the RevenueCat SDK should be reported to [RevenueCat](https://github.com/RevenueCat/purchases-ios/security).
