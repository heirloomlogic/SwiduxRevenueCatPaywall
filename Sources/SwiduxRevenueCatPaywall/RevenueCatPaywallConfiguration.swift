//
//  RevenueCatPaywallConfiguration.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import RevenueCat

/// Namespace for package-level configuration of the RevenueCat-backed paywall.
///
/// Downstream apps call ``RevenueCatPaywall/configure(apiKey:appUserID:userDefaults:logLevel:)``
/// once at launch in place of `Purchases.configure(withAPIKey:)`, which removes the need to
/// `import RevenueCat` from the app target. The RevenueCat SDK becomes an implementation detail
/// of this package.
public enum RevenueCatPaywall {
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

    /// Configures the underlying purchase provider.
    ///
    /// Call once at app launch, before constructing ``RevenueCatPaywallService``. Repeat calls
    /// are ignored, which is safe for SwiftUI `App` re-instantiation and previews.
    ///
    /// - Parameters:
    ///   - apiKey: RevenueCat public SDK key.
    ///   - appUserID: Optional stable identifier for the user. Pass `nil` to let RevenueCat
    ///     generate an anonymous ID.
    ///   - userDefaults: Optional `UserDefaults` for RevenueCat to read and write its cache.
    ///     Pass an app-group `UserDefaults` to share entitlement state with widgets or
    ///     extensions.
    ///   - logLevel: SDK log verbosity. Defaults to `.info`.
    public static func configure(
        apiKey: String,
        appUserID: String? = nil,
        userDefaults: UserDefaults? = nil,
        logLevel: LogLevel = .info
    ) {
        guard !Purchases.isConfigured else { return }

        var builder = Configuration.Builder(withAPIKey: apiKey)
            .with(appUserID: appUserID)
        if let userDefaults {
            builder = builder.with(userDefaults: userDefaults)
        }

        Purchases.configure(with: builder.build())
        Purchases.logLevel = logLevel.rcValue
    }
}
