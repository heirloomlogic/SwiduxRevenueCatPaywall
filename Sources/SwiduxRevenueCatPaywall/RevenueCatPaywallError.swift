//
//  RevenueCatPaywallError.swift
//  SwiduxRevenueCatPaywall
//

import Foundation

/// Errors ``RevenueCatPaywallService`` raises itself, as opposed to those it propagates from the
/// RevenueCat SDK.
public enum RevenueCatPaywallError: Error, Equatable, Sendable {
    /// RevenueCat's entitlement signature verification failed for the response, so it was
    /// altered in transit and nothing in it is trusted.
    ///
    /// Thrown by ``RevenueCatPaywallService/customerInfo()`` and
    /// ``RevenueCatPaywallService/restorePurchases()`` like any other failed read: wrapped in
    /// `ResilientPaywallService`, the read falls back to the last-known-good entitlement (so a
    /// paying user is not flipped to free), and with nothing cached the plugin dispatches
    /// `.refreshFailed`. The stream skips such a response instead. Either way a `.fault` is logged.
    /// See ``RevenueCatPaywall/EntitlementVerification/informational``.
    case verificationFailed
}

extension RevenueCatPaywallError: LocalizedError {
    /// A user-presentable description of the error.
    public var errorDescription: String? {
        switch self {
        case .verificationFailed: "Your purchases couldn't be verified. Please try again later."
        }
    }
}
