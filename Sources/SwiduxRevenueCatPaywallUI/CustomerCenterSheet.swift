//
//  CustomerCenterSheet.swift
//  SwiduxRevenueCatPaywallUI
//

import RevenueCatUI
import SwiduxPaywall
import SwiftUI

/// Drop-in customer-center presentation that adapts to platform support.
///
/// Place anywhere in the view tree (typically `.background`) and bind `isPresented` to
/// `PaywallState.isCustomerCenterPresented`.
///
/// Presentation differs by platform:
///
/// - **iOS** — Presents `RevenueCatUI.CustomerCenterView` in a `sheet`.
/// - **macOS** — RevenueCatUI does not ship a customer center on macOS. This view instead opens
///   `itms-apps://apps.apple.com/account/subscriptions` in App Store and immediately fires
///   `onDismiss`, so the dispatched flow stays symmetric with iOS.
///
/// See the *Platform Behavior* article in the `SwiduxRevenueCatPaywall` documentation for the rationale.
public struct CustomerCenterSheet: View {
    private let isPresented: Bool
    private let onDismiss: () -> Void

    /// Creates a customer-center sheet driven by `PaywallState.isCustomerCenterPresented`.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the sheet is visible. Pass `store.paywall.isCustomerCenterPresented`
    ///     directly.
    ///   - onDismiss: Called when the user dismisses the sheet (or, on macOS, immediately after
    ///     the App Store URL is opened). Dispatch `.paywall(.dismissCustomerCenter)` so the plugin
    ///     clears its presentation state.
    public init(isPresented: Bool, onDismiss: @escaping () -> Void) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
    }

    /// An `EmptyView` plus the platform-appropriate presentation modifier.
    ///
    /// On iOS the body attaches a `sheet` modifier that presents `RevenueCatUI.CustomerCenterView`.
    /// On macOS the body attaches an `onChange` modifier that opens the App Store subscriptions URL
    /// and immediately fires `onDismiss`. The view itself contributes no layout — attach via
    /// `.background`.
    public var body: some View {
        EmptyView()
            #if os(iOS)
        .sheet(isPresented: .constant(isPresented), onDismiss: onDismiss) {
            CustomerCenterView()
        }
            #else
        .onChange(of: isPresented) { _, presented in
            if presented {
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    NSWorkspace.shared.open(url)
                }
                onDismiss()
            }
        }
            #endif
    }
}
