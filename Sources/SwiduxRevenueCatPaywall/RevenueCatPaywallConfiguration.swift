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
/// of this package.
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
    /// Call once at app launch, before constructing ``RevenueCatPaywallService``. Repeat calls
    /// are ignored (with a logged warning), which is safe for SwiftUI `App` re-instantiation
    /// and previews.
    ///
    /// - Parameters:
    ///   - apiKey: RevenueCat public SDK key.
    ///   - appUserID: Optional stable identifier for the user. Pass `nil` to let RevenueCat
    ///     generate an anonymous ID.
    ///   - userDefaults: Optional `UserDefaults` for RevenueCat to read and write its cache.
    ///     Pass an app-group `UserDefaults` to share entitlement state with widgets or
    ///     extensions.
    ///   - logLevel: SDK log verbosity. Defaults to `.info`.
    ///   - entitlementVerification: Signed entitlement verification mode. Defaults to
    ///     `.disabled` (the SDK default); pass `.informational` to detect tampered entitlement
    ///     responses.
    ///   - purchasesAreCompletedBy: Who finishes purchase transactions. Pass `.myApp` when your
    ///     app runs its own StoreKit purchase code and RevenueCat should only observe. Omit for
    ///     the SDK default (`.revenueCat`).
    ///   - storeKitVersion: StoreKit version the SDK uses (and, with
    ///     `purchasesAreCompletedBy: .myApp`, the version your purchase code uses). Omit for
    ///     the SDK default (StoreKit 2).
    public static func configure(
        apiKey: String,
        appUserID: String? = nil,
        userDefaults: UserDefaults? = nil,
        logLevel: LogLevel = .info,
        entitlementVerification: EntitlementVerification = .disabled,
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

        var builder = Configuration.Builder(withAPIKey: apiKey)
            .with(appUserID: appUserID)
            .with(entitlementVerificationMode: entitlementVerification.rcValue)
        if let userDefaults {
            builder = builder.with(userDefaults: userDefaults)
        }
        if let purchasesAreCompletedBy {
            // RevenueCat's builder couples these two settings; when the caller overrides
            // completion without pinning a version, forward the SDK default (StoreKit 2).
            builder = builder.with(
                purchasesAreCompletedBy: purchasesAreCompletedBy.rcValue,
                storeKitVersion: (storeKitVersion ?? .storeKit2).rcValue
            )
        } else if let storeKitVersion {
            builder = builder.with(storeKitVersion: storeKitVersion.rcValue)
        }

        Purchases.configure(with: builder.build())
        Purchases.logLevel = logLevel.rcValue
    }
}
