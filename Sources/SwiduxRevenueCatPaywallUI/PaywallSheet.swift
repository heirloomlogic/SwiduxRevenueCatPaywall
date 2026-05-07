//
//  PaywallSheet.swift
//  SwiduxRevenueCatPaywallUI
//

import RevenueCatUI
import SwiduxPaywall
import SwiftUI

/// Wraps `RevenueCatUI.PaywallView` for presentation driven by `PaywallState.isPresented`.
///
/// Uses `fullScreenCover` on iOS and `sheet` on macOS.
public struct PaywallSheet: View {
    private let isPresented: Bool
    private let onDismiss: () -> Void

    /// Creates a paywall sheet.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the sheet is visible (from `PaywallState.isPresented`).
    ///   - onDismiss: Called when the user dismisses the sheet.
    public init(isPresented: Bool, onDismiss: @escaping () -> Void) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
    }

    public var body: some View {
        EmptyView()
            #if os(iOS)
            .fullScreenCover(isPresented: .constant(isPresented), onDismiss: onDismiss) {
                PaywallView()
            }
            #else
            .sheet(isPresented: .constant(isPresented), onDismiss: onDismiss) {
                PaywallView()
                    .frame(minWidth: 400, minHeight: 600)
            }
            #endif
    }
}
