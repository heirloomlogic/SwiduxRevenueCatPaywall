//
//  RevenueCatPaywallError.swift
//  SwiduxRevenueCatPaywall
//

import Foundation
import SwiduxPaywall

/// Errors ``RevenueCatPaywallService`` raises itself, as opposed to errors it propagates from the RevenueCat SDK.
public enum RevenueCatPaywallError: Error, Equatable, Sendable {
    /// RevenueCat has not been configured, so the requested operation cannot start.
    case notConfigured
    /// The response or a configured entitlement failed signature verification, so no snapshot was produced.
    case verificationFailed
    /// The purchase identity changed while a read or restore was in flight, so its result was discarded instead of being reported for the new identity.
    case identityChanged
}

/// A provider-independent description of the active purchase identity.
public enum RevenueCatPaywallIdentity: Equatable, Sendable {
    /// RevenueCat is using a generated anonymous identity.
    case anonymous
    /// RevenueCat is using the application's stable user identifier.
    case appUserID(String)
}

/// The completed state of a login or logout operation.
public struct RevenueCatPaywallIdentityResult: Equatable, Sendable {
    /// The identity active after the operation.
    public let identity: RevenueCatPaywallIdentity
    /// The mapped entitlement state returned by the provider. Failed signature verification is rejected; `.disabled` accepts responses without a signature check. This is `nil` only when logout is called while already anonymous and no cached customer info passes that policy.
    public let snapshot: EntitlementSnapshot?
    /// Whether the active identity differs from the identity observed before the operation.
    public let identityChanged: Bool
}

/// A package-owned failure from a login or logout operation.
public struct RevenueCatPaywallIdentityError: Error, Equatable, Sendable {
    /// The identity operation that failed.
    public enum Operation: Equatable, Sendable {
        case logIn
        case logOut
    }

    /// A provider-independent reason callers can handle without importing RevenueCat.
    public enum Reason: Equatable, Sendable {
        case notConfigured
        case invalidAppUserID
        case networkUnavailable
        case verificationFailed
        case configuration
        case providerFailure
    }

    /// The operation that failed.
    public let operation: Operation
    /// The mapped failure reason.
    public let reason: Reason
    /// The identity active before the operation, or `nil` when RevenueCat was not configured.
    public let identityBefore: RevenueCatPaywallIdentity?
    /// The identity observed after the failure, or `nil` when RevenueCat was not configured.
    public let identityAfter: RevenueCatPaywallIdentity?
    /// Whether RevenueCat changed identity before reporting the failure.
    public var identityChanged: Bool {
        guard let identityBefore, let identityAfter else { return false }
        return identityBefore != identityAfter
    }

    init(
        operation: Operation,
        reason: Reason,
        identityBefore: RevenueCatPaywallIdentity?,
        identityAfter: RevenueCatPaywallIdentity?
    ) {
        self.operation = operation
        self.reason = reason
        self.identityBefore = identityBefore
        self.identityAfter = identityAfter
    }
}

extension RevenueCatPaywallError: LocalizedError {
    /// A recovery message suitable for display or logging.
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases aren't available yet. Please try again."
        case .verificationFailed:
            "Your purchases couldn't be verified. Please try again later."
        case .identityChanged:
            "Your account changed while purchases were loading. Please try again."
        }
    }
}

extension RevenueCatPaywallIdentityError: LocalizedError {
    /// A recovery message suitable for display or logging.
    public var errorDescription: String? {
        switch reason {
        case .notConfigured:
            "Purchases aren't available yet. Please try again."
        case .invalidAppUserID:
            "The account identifier is invalid."
        case .networkUnavailable:
            "The network became unavailable during the account operation. The active purchase identity may already have changed."
        case .verificationFailed:
            "Purchases couldn't be verified after the account operation. Please try again later."
        case .configuration:
            "The purchase provider isn't configured correctly."
        case .providerFailure:
            "The purchase provider reported an account error. The active purchase identity may already have changed."
        }
    }
}
