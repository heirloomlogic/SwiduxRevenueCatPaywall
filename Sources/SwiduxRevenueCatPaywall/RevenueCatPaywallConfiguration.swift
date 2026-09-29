//
//  RevenueCatPaywallConfiguration.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import OSLog
import RevenueCat
import StoreKit

/// Namespace for package-level configuration of the RevenueCat-backed paywall.
///
/// Downstream apps call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` once at launch in place of `Purchases.configure(withAPIKey:)`, which removes the need to `import RevenueCat` from the app target. The RevenueCat SDK becomes an implementation detail of this package. Apps with authentication switch users through the configured ``RevenueCatPaywallService`` so they also receive mapped entitlements.
public enum RevenueCatPaywall {
    private static let logger = Logger(
        subsystem: "com.heirloomlogic.SwiduxRevenueCatPaywall",
        category: "configuration"
    )

    /// Mirrors `RevenueCat.LogLevel` so callers can tune log verbosity without importing the
    /// RevenueCat module.
    public enum LogLevel: Sendable {
        case verbose, debug, info, warn, error

        var rcValue: RevenueCat.LogLevel {
            switch self {
            case .verbose: .verbose
            case .debug: .debug
            case .info: .info
            case .warn: .warn
            case .error: .error
            }
        }
    }

    /// Mirrors `RevenueCat.Configuration.EntitlementVerificationMode` so callers can opt out of
    /// signed entitlement verification without importing the RevenueCat module.
    public enum EntitlementVerification: Sendable {
        /// No entitlement verification is performed; responses are trusted without a signature check.
        case disabled
        /// Entitlement responses are signature-verified (the SDK default). RevenueCat marks failed verification without failing parsing; ``RevenueCatPaywallService`` rejects the response by throwing on reads and restores or skipping a stream value.
        case informational

        var rcValue: Configuration.EntitlementVerificationMode {
            switch self {
            case .disabled: .disabled
            case .informational: .informational
            }
        }
    }

    /// Mirrors `RevenueCat.PurchasesAreCompletedBy` so callers can take over transaction
    /// finishing without importing the RevenueCat module.
    public enum PurchasesCompletedBy: Sendable {
        /// RevenueCat finishes purchase transactions (the SDK default).
        case revenueCat
        /// Your app makes the purchases and finishes the transactions; RevenueCat observes.
        ///
        /// - Note: ``RevenueCatPaywallService/restorePurchases()`` still uses the SDK's user-initiated `restorePurchases()` flow in this mode so the App Store receipt is refreshed. The bundled UI supports this mode with StoreKit 2 through `RevenueCatPaywallPurchaseLogic`; pass it as `purchaseLogic` to either paywall modifier.
        ///
        /// - Important: For StoreKit 2 purchases made outside the bundled paywall, call ``RevenueCatPaywall/recordPurchase(_:)`` after `Product.purchase()` and before finishing the verified transaction.
        case myApp

        var rcValue: PurchasesAreCompletedBy {
            switch self {
            case .revenueCat: .revenueCat
            case .myApp: .myApp
            }
        }
    }

    /// Mirrors `RevenueCat.StoreKitVersion` so callers can pin a StoreKit version without
    /// importing the RevenueCat module.
    public enum StoreKitVersion: Sendable {
        /// Always use StoreKit 1.
        case storeKit1
        /// Always use StoreKit 2 (the SDK default).
        case storeKit2

        var rcValue: RevenueCat.StoreKitVersion {
            switch self {
            case .storeKit1: .storeKit1
            case .storeKit2: .storeKit2
            }
        }
    }

    /// Configures the underlying purchase provider.
    ///
    /// Call once at app launch. Main-actor isolated so the `Purchases.isConfigured` check-then-act is atomic — the guard and `Purchases.configure` run without an interleaving suspension point. Call before using ``RevenueCatPaywallService`` to read or restore purchases. Repeat calls are ignored (with a logged warning), which is safe for SwiftUI `App` re-instantiation and previews.
    ///
    /// Surrounding whitespace is trimmed from `apiKey`. An empty key, or a secret (`sk_`) key that
    /// must never ship in an app binary, trips an assertion in Debug builds and logs a fault in
    /// Release.
    ///
    /// - Parameters:
    ///   - apiKey: RevenueCat public SDK key.
    ///   - appUserID: Optional stable identifier for the user. Pass `nil` to let RevenueCat
    ///     generate an anonymous ID. For users who sign in after launch, use
    ///     ``logIn(appUserID:)``.
    ///   - userDefaults: Optional `UserDefaults` for RevenueCat to read and write its cache.
    ///     Pass an app-group `UserDefaults` to share entitlement state with widgets or
    ///     extensions.
    ///   - logLevel: SDK log verbosity. Omit for the SDK default (`.debug` in Debug builds,
    ///     `.info` in Release). Applied before the SDK is configured so configuration-time
    ///     diagnostics are emitted at the requested level.
    ///   - entitlementVerification: Signed entitlement verification mode. Defaults to
    ///     `.informational` (the SDK default); the adapter rejects failed verification. Pass `.disabled` to skip verification entirely.
    ///   - purchasesAreCompletedBy: Who finishes purchase transactions. Pass `.myApp` when your
    ///     app runs its own StoreKit purchase code and RevenueCat should only observe. Omit for
    ///     the SDK default (`.revenueCat`).
    ///   - storeKitVersion: StoreKit version the SDK uses (and, with
    ///     `purchasesAreCompletedBy: .myApp`, the version your purchase code uses). Omit for
    ///     the SDK default (StoreKit 2).
    @MainActor
    public static func configure(
        apiKey: String,
        appUserID: String? = nil,
        userDefaults: UserDefaults? = nil,
        logLevel: LogLevel? = nil,
        entitlementVerification: EntitlementVerification = .informational,
        purchasesAreCompletedBy: PurchasesCompletedBy? = nil,
        storeKitVersion: StoreKitVersion? = nil
    ) {
        guard !Purchases.isConfigured else {
            logger.warning(
                """
                RevenueCatPaywall.configure(apiKey:) called after Purchases was already \
                configured; the call is ignored. If this was not a SwiftUI re-instantiation, \
                check for conflicting configure calls.
                """
            )
            return
        }

        // A key pasted with a stray newline would otherwise fail every request's authentication.
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = apiKeyProblem(apiKey) {
            logger.fault("RevenueCatPaywall.configure(apiKey:): \(problem.message, privacy: .public)")
            assertionFailure("RevenueCatPaywall.configure(apiKey:): \(problem.message)")
        }

        // Set verbosity first so the SDK's own configuration diagnostics (key validation,
        // StoreKit mode selection) are emitted at the requested level.
        if let logLevel {
            Purchases.logLevel = logLevel.rcValue
        }
        Purchases.configure(
            with: makeConfiguration(
                apiKey: apiKey,
                appUserID: appUserID,
                userDefaults: userDefaults,
                entitlementVerification: entitlementVerification,
                purchasesAreCompletedBy: purchasesAreCompletedBy,
                storeKitVersion: storeKitVersion
            )
        )
    }

    /// Switches the underlying purchase provider to the given user without returning mapped entitlements.
    ///
    /// New code should use ``RevenueCatPaywallService/logIn(appUserID:)`` so the result includes the verified entitlement snapshot. This compatibility method maps provider failures to ``RevenueCatPaywallIdentityError`` but does not return entitlements.
    @available(
        *, deprecated,
        message: "Use RevenueCatPaywallService.logIn(appUserID:) to receive typed results and errors."
    )
    public static func logIn(appUserID: String) async throws(RevenueCatPaywallIdentityError) {
        guard Purchases.isConfigured else {
            throw RevenueCatPaywallIdentityError(
                operation: .logIn,
                reason: .notConfigured,
                identityBefore: nil,
                identityAfter: nil
            )
        }
        let identityBefore = currentIdentity
        do {
            _ = try await Purchases.shared.logIn(appUserID)
        } catch {
            throw RevenueCatPaywallIdentityError(
                operation: .logIn,
                reason: RevenueCatPaywallService.identityFailureReason(from: error),
                identityBefore: identityBefore,
                identityAfter: currentIdentity
            )
        }
    }

    /// Logs out without returning mapped entitlements.
    ///
    /// New code should use ``RevenueCatPaywallService/logOut()`` so the result includes the verified entitlement snapshot. This compatibility method maps provider failures to ``RevenueCatPaywallIdentityError`` but does not return entitlements, and it retains the already-anonymous no-op.
    @available(
        *, deprecated,
        message: "Use RevenueCatPaywallService.logOut() to receive typed results and errors."
    )
    public static func logOut() async throws(RevenueCatPaywallIdentityError) {
        guard Purchases.isConfigured else {
            throw RevenueCatPaywallIdentityError(
                operation: .logOut,
                reason: .notConfigured,
                identityBefore: nil,
                identityAfter: nil
            )
        }
        guard !Purchases.shared.isAnonymous else { return }
        let identityBefore = currentIdentity
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            throw RevenueCatPaywallIdentityError(
                operation: .logOut,
                reason: RevenueCatPaywallService.identityFailureReason(from: error),
                identityBefore: identityBefore,
                identityAfter: currentIdentity
            )
        }
    }

    /// Reports the result of an app-owned StoreKit 2 purchase to RevenueCat.
    ///
    /// Call this immediately after `Product.purchase()` when configured with `purchasesAreCompletedBy: .myApp` and before finishing a verified transaction. RevenueCat needs the original `Product.PurchaseResult`; reporting only the transaction identifier is not equivalent.
    ///
    /// The bundled UI modifiers call this automatically for purchases made through their `purchaseLogic`. Apps use this entry point for purchases made elsewhere, which keeps the RevenueCat SDK out of the app target.
    ///
    /// - Parameter purchaseResult: The result returned by StoreKit's `Product.purchase()`.
    /// - Throws: Any error propagated from RevenueCat while recording the result.
    /// - Precondition: ``configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)`` has been called.
    public static func recordPurchase(_ purchaseResult: Product.PurchaseResult) async throws {
        precondition(
            Purchases.isConfigured,
            "Call RevenueCatPaywall.configure(apiKey:) before RevenueCatPaywall.recordPurchase(_:)."
        )
        try await recordPurchase(purchaseResult) { result in
            _ = try await Purchases.shared.recordPurchase(result)
        }
    }

    // MARK: - Internal

    private static var currentIdentity: RevenueCatPaywallIdentity {
        Purchases.shared.isAnonymous ? .anonymous : .appUserID(Purchases.shared.appUserID)
    }

    /// A misconfigured API key that ``configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
    /// flags. RevenueCat itself accepts both silently and fails later, or not at all.
    enum APIKeyProblem: Equatable {
        /// Empty or whitespace-only: every SDK request fails authentication.
        case empty
        /// A secret key, which grants server-side API access and must never ship in an app.
        case secret

        var message: String {
            switch self {
            case .empty:
                "The API key is empty. Pass the public SDK key from the RevenueCat dashboard."
            case .secret:
                """
                The API key is a secret (sk_) key, which must never ship in an app binary. \
                Pass the public SDK key from the RevenueCat dashboard and revoke this one.
                """
            }
        }
    }

    static func apiKeyProblem(_ apiKey: String) -> APIKeyProblem? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.hasPrefix("sk_") { return .secret }
        return nil
    }

    static func recordPurchase(
        _ purchaseResult: Product.PurchaseResult,
        using recorder: @Sendable (Product.PurchaseResult) async throws -> Void
    ) async throws {
        try await recorder(purchaseResult)
    }

    /// How ``configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
    /// forwards the coupled `purchasesAreCompletedBy` / `storeKitVersion` pair to RevenueCat's
    /// builder. Extracted as a pure value so the branch logic is unit-testable —
    /// `Purchases.configure` is once-per-process, so only one end-to-end configure path can ever
    /// run in a test suite.
    enum StoreKitSelection: Equatable {
        /// Caller overrode completion; RevenueCat's builder requires a StoreKit version
        /// alongside it, so an unspecified version forwards the SDK default (StoreKit 2).
        case completedBy(PurchasesCompletedBy, StoreKitVersion)
        /// Caller pinned a StoreKit version but left completion at the SDK default.
        case storeKitVersion(StoreKitVersion)
        /// Caller specified neither; leave both builder settings untouched.
        case sdkDefault
    }

    static func storeKitSelection(
        purchasesAreCompletedBy: PurchasesCompletedBy?,
        storeKitVersion: StoreKitVersion?
    ) -> StoreKitSelection {
        if let purchasesAreCompletedBy {
            .completedBy(purchasesAreCompletedBy, storeKitVersion ?? .storeKit2)
        } else if let storeKitVersion {
            .storeKitVersion(storeKitVersion)
        } else {
            .sdkDefault
        }
    }

    static func makeConfiguration(
        apiKey: String,
        appUserID: String?,
        userDefaults: UserDefaults?,
        entitlementVerification: EntitlementVerification,
        purchasesAreCompletedBy: PurchasesCompletedBy?,
        storeKitVersion: StoreKitVersion?
    ) -> Configuration {
        var builder = Configuration.Builder(withAPIKey: apiKey)
            .with(appUserID: appUserID)
            .with(entitlementVerificationMode: entitlementVerification.rcValue)
        if let userDefaults {
            builder = builder.with(userDefaults: userDefaults)
        }
        switch storeKitSelection(
            purchasesAreCompletedBy: purchasesAreCompletedBy,
            storeKitVersion: storeKitVersion
        ) {
        case .completedBy(let completedBy, let version):
            builder = builder.with(
                purchasesAreCompletedBy: completedBy.rcValue,
                storeKitVersion: version.rcValue
            )
        case .storeKitVersion(let version):
            builder = builder.with(storeKitVersion: version.rcValue)
        case .sdkDefault:
            break
        }
        return builder.build()
    }
}
