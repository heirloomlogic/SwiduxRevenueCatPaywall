//
//  CustomerCenterSheet.swift
//  SwiduxRevenueCatPaywallUI
//

import RevenueCatUI
import SwiduxPaywall
import SwiftUI

/// Presents the RevenueCat customer center on iOS, or opens the App Store subscriptions page on macOS.
public struct CustomerCenterSheet: View {
    private let isPresented: Bool
    private let onDismiss: () -> Void

    /// Creates a customer center sheet.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the sheet is visible (from `PaywallState.isCustomerCenterPresented`).
    ///   - onDismiss: Called when the user dismisses the sheet.
    public init(isPresented: Bool, onDismiss: @escaping () -> Void) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
    }

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
