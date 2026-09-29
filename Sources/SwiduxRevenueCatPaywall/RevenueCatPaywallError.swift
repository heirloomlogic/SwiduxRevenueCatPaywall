//
//  RevenueCatPaywallError.swift
//  SwiduxRevenueCatPaywall
//

import Foundation

/// Errors ``RevenueCatPaywallService`` raises itself, as opposed to errors it propagates from the RevenueCat SDK.
public enum RevenueCatPaywallError: Error, Equatable, Sendable {
    /// RevenueCat has not been configured, so the requested operation cannot start.
    case notConfigured
    /// The response or a configured entitlement failed signature verification, so no snapshot was produced.
    case verificationFailed
}

extension RevenueCatPaywallError: LocalizedError {
    /// A recovery message suitable for display or logging.
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases aren't available yet. Please try again."
        case .verificationFailed:
            "Your purchases couldn't be verified. Please try again later."
        }
    }
}
