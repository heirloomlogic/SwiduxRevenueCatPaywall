//
//  PaywallViewModifier.swift
//  SwiduxRevenueCatPaywallUI
//

import OSLog
import RevenueCat
import RevenueCatUI
import SwiduxPaywall
import SwiftUI

#if !os(iOS) && !os(macOS)
#error("SwiduxRevenueCatPaywallUI supports iOS and macOS only.")
#endif

private let logger = Logger(
    subsystem: "com.heirloomlogic.SwiduxRevenueCatPaywall",
    category: "ui"
)

/// Renders `RevenueCatUI.PaywallView`, resolving a specific dashboard offering first when an
/// identifier is provided.
///
/// With a `nil` identifier this is exactly `PaywallView(displayCloseButton:)`, which renders the
/// dashboard's current offering. With an identifier, the offering is fetched on appearance; while
/// it loads a progress indicator shows, and if the fetch fails or the identifier is unknown the
/// view falls back to the current offering (with a logged warning) rather than dead-ending the
/// purchase flow.
struct ResolvedOfferingPaywallView: View {
    let offeringIdentifier: String?
    let displayCloseButton: Bool

    enum Resolution {
        case loading
        case resolved(Offering)
        case currentOffering
    }

    @State private var resolution: Resolution = .loading

    var body: some View {
        if let offeringIdentifier {
            resolvedContent
                .task(id: offeringIdentifier) {
                    resolution = .loading
                    resolution = await Self.resolve(offeringIdentifier)
                }
        } else {
            PaywallView(displayCloseButton: displayCloseButton)
        }
    }

    @ViewBuilder
    private var resolvedContent: some View {
        switch resolution {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .resolved(let offering):
            PaywallView(offering: offering, displayCloseButton: displayCloseButton)
        case .currentOffering:
            PaywallView(displayCloseButton: displayCloseButton)
        }
    }

    private static func resolve(_ identifier: String) async -> Resolution {
        let fetched: Result<Offering?, any Error>
        do {
            fetched = .success(try await Purchases.shared.offerings().offering(identifier: identifier))
        } catch {
            fetched = .failure(error)
        }
        return resolution(from: fetched, identifier: identifier)
    }

    /// Maps the result of the offering fetch to a `Resolution`, logging the fallback reason.
    ///
    /// Pure and separated from the SDK call so the fallback decision is unit-testable.
    static func resolution(from fetched: Result<Offering?, any Error>, identifier: String) -> Resolution {
        switch fetched {
        case .success(let offering?):
            return .resolved(offering)
        case .success(nil):
            // The `privacy: .public` below is deliberate: the identifier is app-supplied
            // dashboard configuration and the error is SDK-generated diagnostics — no user data
            // flows through this path, and the warning exists to diagnose paywall fallbacks from
            // sysdiagnoses without a debugger.
            logger.warning(
                """
                No RevenueCat offering named '\(identifier, privacy: .public)' exists; \
                presenting the current offering instead. Check the identifier against the \
                RevenueCat dashboard.
                """
            )
        case .failure(let error):
            logger.warning(
                """
                Fetching RevenueCat offering '\(identifier, privacy: .public)' failed \
                (\(error, privacy: .public)); presenting the current offering instead.
                """
            )
        }
        return .currentOffering
    }
}

/// Attaches `RevenueCatUI.PaywallView` to the modified view, driven by a `Binding<Bool>`.
///
/// Presents in a `fullScreenCover` on iOS and a 400×600-minimum `sheet` on macOS.
struct RevenueCatPaywallSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let offeringIdentifier: String?
    let displayCloseButton: Bool
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
            ResolvedOfferingPaywallView(
                offeringIdentifier: offeringIdentifier,
                displayCloseButton: displayCloseButton
            )
        }
        #else
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            ResolvedOfferingPaywallView(
                offeringIdentifier: offeringIdentifier,
                displayCloseButton: displayCloseButton
            )
            .frame(minWidth: 400, minHeight: 600)
        }
        #endif
    }
}

/// Attaches `RevenueCatUI.CustomerCenterView` (iOS) or an App Store hand-off (macOS) to the
/// modified view, driven by a `Binding<Bool>`.
struct RevenueCatCustomerCenterSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            CustomerCenterView()
        }
        #else
        // onChange does not fire for the initial value, so a flag that is already true when the
        // view appears (state restoration, modifier attached late) is handled in onAppear.
        content
            .onAppear {
                if isPresented { openAndClear() }
            }
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                openAndClear()
            }
        #endif
    }

    #if os(macOS)
    private func openAndClear() {
        // onAppear/onChange run during view update, where writing `isPresented` back through the
        // binding is undefined behavior ("Modifying state during view update"). Deferring to a
        // main-actor Task also keeps the synchronous NSWorkspace call out of the render pass.
        // Ordering — open, then clear, then onDismiss — is unchanged.
        Task { @MainActor in
            Self.openSubscriptionManagement()
            isPresented = false
            onDismiss?()
        }
    }

    /// Opens App Store subscription management, falling back to the web URL when nothing on
    /// the system claims the `itms-apps` scheme.
    static func openSubscriptionManagement() {
        let appStore = URL(string: "itms-apps://apps.apple.com/account/subscriptions")
        if let appStore, NSWorkspace.shared.open(appStore) { return }
        if let web = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(web)
        }
    }
    #endif
}

/// Composes paywall and customer-center sheets onto a view, driven by `PaywallState`.
///
/// The two presentations are mutually exclusive — the paywall wins. Presenting both surfaces at
/// once would make the platform refuse the second presentation while its state flag silently
/// stuck `true`; instead, a paywall request while the customer center is up (or vice versa)
/// dispatches `.dismissCustomerCenter` so state and screen stay in agreement.
struct RevenueCatPaywallModifier: ViewModifier {
    let state: PaywallState
    let offeringIdentifier: String?
    let displayCloseButton: Bool
    let send: (PaywallAction) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(
                RevenueCatPaywallSheetModifier(
                    isPresented: paywallBinding,
                    offeringIdentifier: offeringIdentifier,
                    displayCloseButton: displayCloseButton,
                    onDismiss: nil
                )
            )
            .modifier(
                RevenueCatCustomerCenterSheetModifier(
                    isPresented: customerCenterBinding,
                    onDismiss: nil
                )
            )
            .onChange(of: state.isPresented) { _, presented in
                if presented, state.isCustomerCenterPresented { send(.dismissCustomerCenter) }
            }
            .onChange(of: state.isCustomerCenterPresented) { _, presented in
                if presented, state.isPresented { send(.dismissCustomerCenter) }
            }
    }

    var paywallBinding: Binding<Bool> {
        Binding(
            get: { state.isPresented },
            set: { newValue in if !newValue { send(.dismiss) } }
        )
    }

    /// Reads `false` while the paywall is presented so the platform is never asked to present
    /// both surfaces at once, even within the single update where both flags are true.
    var customerCenterBinding: Binding<Bool> {
        Binding(
            get: { state.isCustomerCenterPresented && !state.isPresented },
            set: { newValue in if !newValue { send(.dismissCustomerCenter) } }
        )
    }
}

extension View {
    /// Attaches the RevenueCat paywall as a platform-appropriate sheet.
    ///
    /// Presents `RevenueCatUI.PaywallView` in a `fullScreenCover` on iOS and a 400×600-minimum
    /// `sheet` on macOS. The binding's setter is called with `false` when the user dismisses,
    /// so wire it to clear `PaywallState.isPresented` (typically by dispatching `.paywall(.dismiss)`).
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(
    ///         isPresented: Binding(
    ///             get: { store.paywall.isPresented },
    ///             set: { if !$0 { store.send(.paywall(.dismiss)) } }
    ///         )
    ///     )
    /// ```
    ///
    /// See ``revenueCatPaywall(state:offeringIdentifier:displayCloseButton:send:)`` for the
    /// convenience overload that builds the binding for you.
    ///
    /// - Parameters:
    ///   - isPresented: Two-way binding to the paywall's visibility flag.
    ///   - offeringIdentifier: Identifier of the RevenueCat offering to present — for example a
    ///     win-back or regional offering. Pass `nil` (the default) for the dashboard's current
    ///     offering. An unknown identifier or a failed fetch falls back to the current offering
    ///     with a logged warning.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`;
    ///     neither the iOS `fullScreenCover` nor the macOS `sheet` offers any other dismissal
    ///     affordance, so pass `false` only for a hard paywall the user must purchase through.
    ///   - onDismiss: Optional callback fired after the sheet dismisses.
    /// - Returns: A view with the paywall sheet attached.
    public func revenueCatPaywall(
        isPresented: Binding<Bool>,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            RevenueCatPaywallSheetModifier(
                isPresented: isPresented,
                offeringIdentifier: offeringIdentifier,
                displayCloseButton: displayCloseButton,
                onDismiss: onDismiss
            )
        )
    }

    /// Attaches the RevenueCat customer center as a platform-appropriate sheet.
    ///
    /// On iOS, presents `RevenueCatUI.CustomerCenterView` in a `sheet`. On macOS, opens
    /// `itms-apps://apps.apple.com/account/subscriptions` in App Store (falling back to the
    /// `https://apps.apple.com/account/subscriptions` web URL if nothing handles the scheme)
    /// and immediately clears the binding (so `isCustomerCenterPresented` does not stick
    /// `true`) before firing `onDismiss`.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatCustomerCenter(
    ///         isPresented: Binding(
    ///             get: { store.paywall.isCustomerCenterPresented },
    ///             set: { if !$0 { store.send(.paywall(.dismissCustomerCenter)) } }
    ///         )
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: Two-way binding to the customer center's visibility flag.
    ///   - onDismiss: Optional callback fired after dismissal (or, on macOS, after the App Store
    ///     URL is opened).
    /// - Returns: A view with the customer-center sheet attached.
    public func revenueCatCustomerCenter(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            RevenueCatCustomerCenterSheetModifier(isPresented: isPresented, onDismiss: onDismiss)
        )
    }

    /// Attaches both the paywall and customer-center sheets driven by `PaywallState`.
    ///
    /// Convenience modifier that composes ``revenueCatPaywall(isPresented:offeringIdentifier:displayCloseButton:onDismiss:)``
    /// and ``revenueCatCustomerCenter(isPresented:onDismiss:)`` in one call. Each sheet's binding
    /// dispatches the matching dismiss action when the system clears it: `.dismiss` for the
    /// paywall, `.dismissCustomerCenter` for the customer center.
    ///
    /// The two presentations are mutually exclusive; the paywall wins. If one surface is
    /// requested while the other is up, `.dismissCustomerCenter` is dispatched so
    /// `PaywallState` never holds a presentation flag the platform refused to honor.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
    /// ```
    ///
    /// - Parameters:
    ///   - state: The paywall slice from your store, typically `store.paywall`.
    ///   - offeringIdentifier: Identifier of the RevenueCat offering to present — for example a
    ///     win-back or regional offering. Pass `nil` (the default) for the dashboard's current
    ///     offering. An unknown identifier or a failed fetch falls back to the current offering
    ///     with a logged warning.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`;
    ///     neither the iOS `fullScreenCover` nor the macOS `sheet` offers any other dismissal
    ///     affordance, so pass `false` only for a hard paywall the user must purchase through.
    ///   - send: A closure that lifts a `PaywallAction` into your root action and dispatches it,
    ///     for example `{ store.send(.paywall($0)) }`.
    /// - Returns: A view with both the paywall and customer-center sheets attached.
    public func revenueCatPaywall(
        state: PaywallState,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        send: @escaping (PaywallAction) -> Void
    ) -> some View {
        modifier(
            RevenueCatPaywallModifier(
                state: state,
                offeringIdentifier: offeringIdentifier,
                displayCloseButton: displayCloseButton,
                send: send
            )
        )
    }
}
