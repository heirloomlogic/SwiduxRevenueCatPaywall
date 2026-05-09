//
//  PaywallSheet.swift
//  SwiduxRevenueCatPaywallUI
//

import RevenueCatUI
import SwiduxPaywall
import SwiftUI

/// Drop-in paywall presentation backed by `RevenueCatUI.PaywallView`.
///
/// Place anywhere in the view tree (typically `.background`) and bind `isPresented` to
/// `PaywallState.isPresented`. The sheet appears when the value is `true` and dismisses via
/// the system gesture, which fires `onDismiss`.
///
/// Presentation differs by platform:
///
/// - **iOS** — `fullScreenCover` so the paywall takes the full screen.
/// - **macOS** — `sheet` sized to a 400×600 minimum, since macOS sheets do not expand to fill
///   the parent window.
///
/// See the *Platform Behavior* article in the `SwiduxRevenueCatPaywall` documentation for the rationale.
public struct PaywallSheet: View {
    private let isPresented: Bool
    private let onDismiss: () -> Void

    /// Creates a paywall sheet driven by `PaywallState.isPresented`.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the sheet is visible. Pass `store.paywall.isPresented` directly —
    ///     the plugin owns this flag.
    ///   - onDismiss: Called when the user dismisses the sheet. Dispatch `.paywall(.dismiss)` so
    ///     the plugin clears its presentation state and triggers an entitlement refresh.
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
