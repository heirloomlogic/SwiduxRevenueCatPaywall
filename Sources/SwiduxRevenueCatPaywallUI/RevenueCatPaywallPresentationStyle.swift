//
//  RevenueCatPaywallPresentationStyle.swift
//  SwiduxRevenueCatPaywallUI
//

import SwiftUI

/// Controls how the bundled paywall is presented.
public enum RevenueCatPaywallPresentationStyle: Sendable {
    /// Uses a sheet at regular iOS width, a full-screen cover at compact iOS width, and a sheet on macOS.
    case automatic
    /// Uses a sheet.
    case sheet
    #if os(iOS)
    /// Uses a full-screen cover.
    case fullScreen
    #endif
}

enum RevenueCatPaywallPresentationKind: Equatable {
    case sheet
    #if os(iOS)
    case fullScreen
    #endif
}

extension RevenueCatPaywallPresentationStyle {
    #if os(iOS)
    func resolved(horizontalSizeClass: UserInterfaceSizeClass?) -> RevenueCatPaywallPresentationKind {
        switch self {
        case .automatic:
            horizontalSizeClass == .regular ? .sheet : .fullScreen
        case .sheet:
            .sheet
        case .fullScreen:
            .fullScreen
        }
    }
    #else
    func resolved() -> RevenueCatPaywallPresentationKind { .sheet }
    #endif
}
