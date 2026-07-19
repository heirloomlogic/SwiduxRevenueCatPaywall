//
//  RevenueCatPaywallConfiguration.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import OSLog
import RevenueCat

/// Namespace for package-level configuration of the RevenueCat-backed paywall.
///
/// Downstream apps call
/// ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
/// once at launch in place of `Purchases.configure(withAPIKey:)`, which removes the need to
/// `import RevenueCat` from the app target. The RevenueCat SDK becomes an implementation detail
/// of this package. Apps with authentication switch users through
/// ``RevenueCatPaywall/logIn(appUserID:)`` and ``RevenueCatPaywall/logOut()`` for the same
/// reason.
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

    /// Mirrors `RevenueCat.Configuration.EntitlementVerificationMode` so callers can enable
    /// signed entitlement verification without importing the RevenueCat module.
    public enum EntitlementVerification: Sendable {
        /// No entitlement verification is performed.
        case disabled
        /// Entitlement responses are signature-verified; a failed verification is reported on
        /// the result but parsing does not fail, so you can observe tampering without locking
        /// users out.
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
        /// - Note: In this mode ``RevenueCatPaywallService/restorePurchases()`` automatically
        ///   uses the SDK's `syncPurchases()` instead of `restorePurchases()`, which in observer
        ///   mode can alias or transfer purchases between accounts in ways a sync would not. Restore
        ///   dispatches therefore remain safe.
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
    /// Call once at app launch. Main-actor isolated so the `Purchases.isConfigured` check-then-act
    /// is atomic — the guard and `Purchases.configure` run without an interleaving suspension
    /// point. Call before constructing ``RevenueCatPaywallService``. Repeat calls are ignored (with
    /// a logged warning), which is safe for SwiftUI `App` re-instantiation and previews.
    ///
    /// - Parameters:
    ///   - apiKey: RevenueCat public SDK key.
    ///   - appUserID: Optional stable identifier for the user. Pass `nil` to let RevenueCat
    ///     generate an anonymous ID. For users who sign in after launch, use
    ///     ``logIn(appUserID:)``.
    ///   - userDefaults: Optional `UserDefaults` for RevenueCat to read and write its cache.
    ///     Pass an app-group `UserDefaults` to share entitlement state with widgets or
    ///     extensions.
    ///   - logLevel: SDK log verbosity. Defaults to `.info`. Applied before the SDK is
    ///     configured so configuration-time diagnostics are emitted at the requested level.
    ///   - entitlementVerification: Signed entitlement verification mode. Defaults to
    ///     `.informational`, which detects tampered entitlement responses without ever locking
    ///     users out; pass `.disabled` to skip verification entirely (the SDK default).
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
        logLevel: LogLevel = .info,
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

        // Set verbosity first so the SDK's own configuration diagnostics (key validation,
        // StoreKit mode selection) are emitted at the requested level.
        Purchases.logLevel = logLevel.rcValue
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

    /// Switches the underlying purchase provider to the given user.
    ///
    /// Call after sign-in, in place of `Purchases.shared.logIn(_:)`, so the app target never
    /// imports RevenueCat. The entitlement stream
    /// (``RevenueCatPaywallService/customerInfoStream()``) delivers the new user's entitlements;
    /// no manual refresh is needed.
    ///
    /// - Parameter appUserID: Stable identifier for the signed-in user.
    /// - Throws: Any error propagated from `Purchases.shared.logIn(_:)`.
    /// - Precondition: ``configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
    ///   has been called.
    public static func logIn(appUserID: String) async throws {
        precondition(
            Purchases.isConfigured,
            "Call RevenueCatPaywall.configure(apiKey:) before RevenueCatPaywall.logIn(appUserID:)."
        )
        _ = try await Purchases.shared.logIn(appUserID)
    }

    /// Logs the current user out of the underlying purchase provider, resetting to a new
    /// anonymous user.
    ///
    /// Call after sign-out, in place of `Purchases.shared.logOut()`. The entitlement stream
    /// delivers the anonymous user's (typically empty) entitlements; no manual refresh is
    /// needed.
    ///
    /// - Throws: Any error propagated from `Purchases.shared.logOut()`, including when the
    ///   current user is already anonymous.
    /// - Precondition: ``configure(apiKey:appUserID:userDefaults:logLevel:entitlementVerification:purchasesAreCompletedBy:storeKitVersion:)``
    ///   has been called.
    public static func logOut() async throws {
        precondition(
            Purchases.isConfigured,
            "Call RevenueCatPaywall.configure(apiKey:) before RevenueCatPaywall.logOut()."
        )
        _ = try await Purchases.shared.logOut()
    }

    // MARK: - Internal

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
