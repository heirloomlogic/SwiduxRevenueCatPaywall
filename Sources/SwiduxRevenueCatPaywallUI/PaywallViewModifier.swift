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

/// Renders `RevenueCatUI.PaywallView`, resolving an explicit offering or RevenueCat placement first.
///
/// An explicit offering identifier takes precedence over a placement. Cached offerings render immediately; other selections are fetched while a progress indicator shows. An unknown explicit identifier asserts in Debug, then falls back to the current offering with a warning. Fetch failures also fall back. Without a configured `Purchases` (previews and tests), the view defers to `PaywallView`'s own unconfigured-SDK handling.
///
/// `onRestoreCompleted` fires when RevenueCatUI reports a finished restore, after the user acknowledges its success alert and also when the restore found nothing.
struct ResolvedOfferingPaywallView: View {
    let offeringIdentifier: String?
    let placementIdentifier: String?
    let displayCloseButton: Bool
    let fonts: any PaywallFontProvider
    let purchaseLogic: RevenueCatPaywallPurchaseLogic?
    let onEvent: RevenueCatPaywallEventHandler?
    let onRestoreCompleted: (() -> Void)?
    let onRequestDismiss: (() -> Void)?

    enum Resolution {
        case loading
        case resolved(Offering)
        case currentOffering
    }

    @State private var resolution: Resolution

    init(
        offeringIdentifier: String?,
        placementIdentifier: String? = nil,
        displayCloseButton: Bool,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        onRestoreCompleted: (() -> Void)? = nil,
        onRequestDismiss: (() -> Void)? = nil
    ) {
        self.offeringIdentifier = offeringIdentifier
        self.placementIdentifier = placementIdentifier
        self.displayCloseButton = displayCloseButton
        self.fonts = fonts
        self.purchaseLogic = purchaseLogic
        self.onEvent = onEvent
        self.onRestoreCompleted = onRestoreCompleted
        self.onRequestDismiss = onRequestDismiss
        _resolution = State(
            initialValue: Self.cachedResolution(
                offeringIdentifier: offeringIdentifier,
                placementIdentifier: placementIdentifier
            ) ?? .loading
        )
    }

    var body: some View {
        paywall
            .onPurchaseCompleted { transaction, customerInfo in
                onEvent?(.purchaseCompleted(transaction: transaction, customerInfo: customerInfo))
            }
            .onPurchaseCancelled { onEvent?(.purchaseCancelled) }
            .onPurchaseFailure { onEvent?(.purchaseFailed($0)) }
            .onRestoreCompleted { customerInfo in
                onEvent?(.restoreCompleted(customerInfo: customerInfo))
                onRestoreCompleted?()
            }
            .onRestoreFailure { onEvent?(.restoreFailed($0)) }
            #if os(macOS)
        .onExitCommand {
            Self.handleExitCommand(
                displayCloseButton: displayCloseButton,
                onRequestDismiss: onRequestDismiss
            )
        }
            #endif
    }

    @ViewBuilder
    private var paywall: some View {
        let handlers = Self.handlers(purchaseLogic: purchaseLogic)
        if offeringIdentifier != nil || placementIdentifier != nil {
            resolvedContent
                .task(id: resolutionRequest) {
                    if let cached = Self.cachedResolution(
                        offeringIdentifier: offeringIdentifier,
                        placementIdentifier: placementIdentifier
                    ) {
                        resolution = cached
                        return
                    }
                    resolution = .loading
                    let resolved = await Self.resolve(
                        offeringIdentifier: offeringIdentifier,
                        placementIdentifier: placementIdentifier
                    )
                    // A superseded fetch must not overwrite the newer identifier's resolution.
                    guard !Task.isCancelled else { return }
                    resolution = resolved
                }
        } else {
            PaywallView(
                fonts: fonts,
                displayCloseButton: displayCloseButton,
                performPurchase: handlers.purchase,
                performRestore: handlers.restore
            )
        }
    }

    @ViewBuilder
    private var resolvedContent: some View {
        switch resolution {
        case .loading:
            ProgressView()
                .accessibilityLabel(Text("Loading subscription options"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .resolved(let offering):
            let handlers = Self.handlers(purchaseLogic: purchaseLogic)
            PaywallView(
                offering: offering,
                fonts: fonts,
                displayCloseButton: displayCloseButton,
                performPurchase: handlers.purchase,
                performRestore: handlers.restore
            )
        case .currentOffering:
            let handlers = Self.handlers(purchaseLogic: purchaseLogic)
            PaywallView(
                fonts: fonts,
                displayCloseButton: displayCloseButton,
                performPurchase: handlers.purchase,
                performRestore: handlers.restore
            )
        }
    }

    private static func handlers(
        purchaseLogic: RevenueCatPaywallPurchaseLogic?
    ) -> ObserverModePaywallHandlers {
        let completedBy = Purchases.isConfigured ? Purchases.shared.purchasesAreCompletedBy : .revenueCat
        return ObserverModePaywallAdapter.handlers(for: completedBy, purchaseLogic: purchaseLogic)
    }

    private struct ResolutionRequest: Equatable {
        let offeringIdentifier: String?
        let placementIdentifier: String?
    }

    /// Value used to restart resolution when an offering identifier or placement changes.
    private var resolutionRequest: ResolutionRequest {
        ResolutionRequest(
            offeringIdentifier: offeringIdentifier,
            placementIdentifier: placementIdentifier
        )
    }

    private static func cachedResolution(
        offeringIdentifier: String?,
        placementIdentifier: String?
    ) -> Resolution? {
        guard Purchases.isConfigured, let offerings = Purchases.shared.cachedOfferings else { return nil }
        if let offeringIdentifier,
            let offering = offerings.offering(identifier: offeringIdentifier)
        {
            return .resolved(offering)
        }
        if offeringIdentifier == nil, let placementIdentifier,
            let offering = offerings.currentOffering(forPlacement: placementIdentifier)
        {
            return .resolved(offering)
        }
        return nil
    }

    private static func resolve(
        offeringIdentifier: String?,
        placementIdentifier: String?
    ) async -> Resolution {
        // `Purchases.shared` traps when unconfigured. `PaywallView` reports that state itself.
        guard Purchases.isConfigured else { return .currentOffering }
        do {
            let offerings = try await Purchases.shared.offerings()
            if let offeringIdentifier {
                return resolution(
                    from: .success(offerings.offering(identifier: offeringIdentifier)),
                    identifier: offeringIdentifier
                )
            }
            if let placementIdentifier,
                let offering = offerings.currentOffering(forPlacement: placementIdentifier) ?? offerings.current
            {
                return .resolved(offering)
            }
            return .currentOffering
        } catch {
            if let offeringIdentifier {
                return resolution(from: .failure(error), identifier: offeringIdentifier)
            }
            return .currentOffering
        }
    }

    /// Maps the result of the offering fetch to a `Resolution`, logging the fallback reason.
    ///
    /// Pure and separated from the SDK call so the fallback decision is unit-testable.
    static func resolution(from fetched: Result<Offering?, any Error>, identifier: String) -> Resolution {
        resolution(from: fetched, identifier: identifier) { missingIdentifier in
            assertionFailure("No RevenueCat offering named '\(missingIdentifier)' exists")
        }
    }

    static func resolution(
        from fetched: Result<Offering?, any Error>,
        identifier: String,
        assertMissing: (String) -> Void
    ) -> Resolution {
        // RevenueCat's continuation can resume after SwiftUI cancels a superseded task. Keep the
        // old request from asserting or logging after its result is no longer relevant.
        guard !Task.isCancelled else { return .currentOffering }
        switch fetched {
        case .success(let offering?):
            return .resolved(offering)
        case .success(nil):
            assertMissing(identifier)
            // The identifier is logged `.public` deliberately: it is app-supplied dashboard
            // configuration, and the warning exists to diagnose paywall fallbacks from
            // sysdiagnoses without a debugger.
            logger.warning(
                """
                No RevenueCat offering named '\(identifier, privacy: .public)' exists; \
                presenting the current offering instead. Check the identifier against the \
                RevenueCat dashboard.
                """
            )
        case .failure(let error):
            // The domain and code identify the failure publicly; the description stays private
            // because RevenueCat embeds request paths, which carry the app user ID.
            let nsError = error as NSError
            logger.warning(
                """
                Fetching RevenueCat offering '\(identifier, privacy: .public)' failed \
                (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public): \
                \(nsError.localizedDescription, privacy: .private)); presenting the current \
                offering instead.
                """
            )
        }
        return .currentOffering
    }

    #if os(macOS)
    static func handleExitCommand(
        displayCloseButton: Bool,
        onRequestDismiss: (() -> Void)?
    ) {
        guard displayCloseButton else { return }
        onRequestDismiss?()
    }
    #endif
}

/// Attaches `RevenueCatUI.PaywallView` to the modified view, driven by a `Binding<Bool>`.
///
/// Uses the selected iOS presentation style and a 400×600-minimum sheet on macOS.
struct RevenueCatPaywallSheetModifier: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Binding var isPresented: Bool
    let offeringIdentifier: String?
    let placementIdentifier: String?
    let displayCloseButton: Bool
    let fonts: any PaywallFontProvider
    let presentationStyle: RevenueCatPaywallPresentationStyle
    let purchaseLogic: RevenueCatPaywallPurchaseLogic?
    let onEvent: RevenueCatPaywallEventHandler?
    let onDismiss: (() -> Void)?
    var onRestoreCompleted: (() -> Void)? = nil

    func body(content: Content) -> some View {
        #if os(iOS)
        switch presentationStyle.resolved(horizontalSizeClass: horizontalSizeClass) {
        case .sheet:
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) { paywall }
        case .fullScreen:
            content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) { paywall }
        }
        #else
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) { paywall }
        #endif
    }

    private var paywall: some View {
        ResolvedOfferingPaywallView(
            offeringIdentifier: offeringIdentifier,
            placementIdentifier: placementIdentifier,
            displayCloseButton: displayCloseButton,
            fonts: fonts,
            purchaseLogic: purchaseLogic,
            onEvent: onEvent,
            onRestoreCompleted: onRestoreCompleted,
            onRequestDismiss: { isPresented = false }
        )
        #if os(iOS)
        .interactiveDismissDisabled(!displayCloseButton)
        #else
        .frame(minWidth: 400, minHeight: 600)
        #endif
    }
}

/// Attaches `RevenueCatUI.CustomerCenterView` (iOS) or an App Store hand-off (macOS) to the
/// modified view, driven by a `Binding<Bool>`.
struct RevenueCatCustomerCenterSheetModifier: ViewModifier {
    @Environment(\.openURL) private var openURL
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    var onOpenSubscriptionManagement: (() -> Void)? = nil

    #if os(macOS)
    @State private var handledPresentation = false
    #endif

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
                if isPresented { consumePresentation() }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    consumePresentation()
                } else {
                    handledPresentation = false
                }
            }
        #endif
    }

    #if os(macOS)
    func consumePresentation() {
        guard !handledPresentation else { return }
        handledPresentation = true
        // onAppear/onChange run during view update, where writing `isPresented` back through the
        // binding is undefined behavior ("Modifying state during view update"). The task keeps
        // the open, clear, and dismissal callbacks ordered outside the render pass.
        Task { @MainActor in
            if let onOpenSubscriptionManagement {
                onOpenSubscriptionManagement()
            } else {
                openSubscriptionManagement()
            }
            isPresented = false
            onDismiss?()
        }
    }

    func openSubscriptionManagement() {
        guard let appStore = URL(string: "itms-apps://apps.apple.com/account/subscriptions") else {
            return
        }
        openURL(appStore) { accepted in
            guard !accepted, let web = URL(string: "https://apps.apple.com/account/subscriptions") else {
                return
            }
            openURL(web)
        }
    }
    #endif
}

/// Composes paywall and customer-center presentation onto a view, driven by `PaywallState`.
///
/// On iOS the two presentations are mutually exclusive and the paywall wins. On macOS subscription management is an external App Store hand-off, so it can be requested while the paywall sheet is open; the modifier dispatches `.openManageSubscriptions` and then `.dismissCustomerCenter`.
///
/// The paywall also closes after a restore that leaves the user entitled. RevenueCatUI dismisses
/// after a purchase but not after a restore, which would otherwise strand a restoring user — with
/// no way out at all behind a hard paywall (`displayCloseButton: false`). Closing waits for
/// RevenueCatUI's restore completion, which follows the user's acknowledgement of its success
/// alert, and for the entitlement stream to report the restored access, whichever comes last.
struct RevenueCatPaywallModifier: ViewModifier {
    let state: PaywallState
    let offeringIdentifier: String?
    let displayCloseButton: Bool
    let fonts: any PaywallFontProvider
    let presentationStyle: RevenueCatPaywallPresentationStyle
    let purchaseLogic: RevenueCatPaywallPurchaseLogic?
    let onEvent: RevenueCatPaywallEventHandler?
    let send: (PaywallAction) -> Void

    /// Restores RevenueCatUI has reported since the paywall was last presented. A counter rather
    /// than a flag so a second restore in the same presentation still registers as a change.
    @State private var completedRestores = 0

    init(
        state: PaywallState,
        offeringIdentifier: String?,
        displayCloseButton: Bool,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        presentationStyle: RevenueCatPaywallPresentationStyle = .automatic,
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        send: @escaping (PaywallAction) -> Void
    ) {
        self.state = state
        self.offeringIdentifier = offeringIdentifier
        self.displayCloseButton = displayCloseButton
        self.fonts = fonts
        self.presentationStyle = presentationStyle
        self.purchaseLogic = purchaseLogic
        self.onEvent = onEvent
        self.send = send
    }

    func body(content: Content) -> some View {
        content
            .modifier(
                RevenueCatPaywallSheetModifier(
                    isPresented: paywallBinding,
                    offeringIdentifier: offeringIdentifier,
                    placementIdentifier: placementIdentifier,
                    displayCloseButton: displayCloseButton,
                    fonts: fonts,
                    presentationStyle: presentationStyle,
                    purchaseLogic: purchaseLogic,
                    onEvent: onEvent,
                    onDismiss: nil,
                    onRestoreCompleted: { completedRestores += 1 }
                )
            )
            .modifier(
                RevenueCatCustomerCenterSheetModifier(
                    isPresented: customerCenterBinding,
                    onDismiss: nil,
                    onOpenSubscriptionManagement: {
                        send(.openManageSubscriptions)
                    }
                )
            )
            .onAppear {
                for action in Self.reconcilingActions(
                    from: PaywallState(),
                    to: state,
                    restoreCompleted: false
                ) {
                    send(action)
                }
            }
            .onChange(of: completedRestores) { _, count in
                if count > 0, Self.closesAfterRestore(state) { send(.dismiss) }
            }
            .onChange(of: state) { old, new in
                if !new.isPresented { completedRestores = 0 }
                let restoreCompleted = completedRestores > 0
                for action in Self.reconcilingActions(from: old, to: new, restoreCompleted: restoreCompleted) {
                    send(action)
                }
            }
    }

    var placementIdentifier: String? {
        offeringIdentifier == nil ? state.requestedReason : nil
    }

    /// Whether a completed restore should close the paywall given the current state.
    static func closesAfterRestore(_ state: PaywallState) -> Bool {
        state.isPresented && state.isGateSatisfied
    }

    /// Actions that bring presentation back in line with a state transition.
    ///
    /// Pure so the reconciliation rules are unit-testable without hosting a view.
    ///
    /// - Parameters:
    ///   - old: The state before the transition.
    ///   - new: The state after the transition.
    ///   - restoreCompleted: Whether RevenueCatUI has reported a completed restore since the
    ///     paywall was presented. The paywall closes when the entitlement arrives after that
    ///     completion; a gate change on its own (a launch read, a cache seed) never closes it, so
    ///     an entitled user can still open the paywall — for example to add a lifetime license.
    /// - Returns: The actions to dispatch, in order; empty when state and screen already agree.
    static func reconcilingActions(
        from old: PaywallState,
        to new: PaywallState,
        restoreCompleted: Bool
    ) -> [PaywallAction] {
        var actions: [PaywallAction] = []
        if restoreCompleted, new.isPresented, new.isGateSatisfied, !old.isGateSatisfied {
            actions.append(.dismiss)
        }
        #if os(iOS)
        if new.isPresented, new.isCustomerCenterPresented,
            !(old.isPresented && old.isCustomerCenterPresented)
        {
            actions.append(.dismissCustomerCenter)
        }
        #endif
        return actions
    }

    var paywallBinding: Binding<Bool> {
        Binding(
            get: { state.isPresented },
            set: { newValue in if !newValue { send(.dismiss) } }
        )
    }

    /// Applies iOS modal exclusivity while leaving the macOS external hand-off available.
    var customerCenterBinding: Binding<Bool> {
        Binding(
            get: {
                #if os(iOS)
                state.isCustomerCenterPresented && !state.isPresented
                #else
                state.isCustomerCenterPresented
                #endif
            },
            set: { newValue in if !newValue { send(.dismissCustomerCenter) } }
        )
    }
}

extension View {
    /// Attaches the RevenueCat paywall using a platform-appropriate presentation.
    ///
    /// The automatic style uses a full-screen cover at compact iOS width, a sheet at regular iOS width, and a 400×600-minimum sheet on macOS. The binding's setter is called with `false` when the user dismisses, so wire it to clear `PaywallState.isPresented` (typically by dispatching `.paywall(.dismiss)`).
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
    /// See the `PaywallState` overload for convenience wiring that builds the binding.
    ///
    /// - Parameters:
    ///   - isPresented: Two-way binding to the paywall's visibility flag.
    ///   - offeringIdentifier: Identifier of the RevenueCat offering to present, for example a win-back or regional offering. Pass `nil` (the default) for the dashboard's current offering. An unknown identifier asserts in Debug, logs a warning, and falls back to the current offering. A failed fetch falls back with a warning but does not assert.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`; when `false`, iOS sheets disable interactive dismissal, and the iOS full-screen cover and macOS sheet provide no other dismissal affordance. Pass `false` only for a hard paywall the user must purchase through.
    ///     RevenueCatUI dismisses after a purchase but not after a restore; with this overload,
    ///     clearing the binding when the user becomes entitled is up to you (the
    ///     state-driven overload does it for you).
    ///   - fonts: RevenueCatUI font provider used by the paywall.
    ///   - presentationStyle: Automatic or explicit iOS presentation style. macOS always uses a sheet.
    ///   - purchaseLogic: App-owned StoreKit 2 purchase and restore operations for `.myApp` mode. Leave `nil` when RevenueCat completes purchases.
    ///   - onEvent: Optional callback for package-owned purchase, restore, cancellation, and failure values.
    ///   - onDismiss: Optional callback fired after the sheet dismisses.
    /// - Returns: A view with the paywall sheet attached.
    public func revenueCatPaywall(
        isPresented: Binding<Bool>,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        presentationStyle: RevenueCatPaywallPresentationStyle = .automatic,
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            RevenueCatPaywallSheetModifier(
                isPresented: isPresented,
                offeringIdentifier: offeringIdentifier,
                placementIdentifier: nil,
                displayCloseButton: displayCloseButton,
                fonts: fonts,
                presentationStyle: presentationStyle,
                purchaseLogic: purchaseLogic,
                onEvent: onEvent,
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

    /// Attaches paywall and customer-center presentation driven by `PaywallState`.
    ///
    /// Convenience modifier that composes paywall and customer-center presentation in one call. Presentation changes dispatch their matching paywall actions through `send`.
    ///
    /// On iOS the two presentations are mutually exclusive and the paywall wins. On macOS a customer-center request dispatches `.openManageSubscriptions` through the paywall plugin, then `.dismissCustomerCenter`; the external App Store hand-off does not compete with the paywall sheet.
    ///
    /// Attach this modifier once, to one app-wide presentation host. Attaching it to every `WindowGroup` scene or window causes every attachment to respond to the same `PaywallState` request.
    ///
    /// After a restore inside the paywall, the modifier dispatches `.dismiss` once
    /// `PaywallState.isGateSatisfied` is `true`, since RevenueCatUI does not dismiss after a
    /// restore on its own. This relies on the entitlement stream: dispatch
    /// `.observeCustomerInfo` at launch.
    ///
    /// ```swift
    /// ContentView()
    ///     .revenueCatPaywall(state: store.paywall) { store.send(.paywall($0)) }
    /// ```
    ///
    /// - Parameters:
    ///   - state: The paywall slice from your store, typically `store.paywall`.
    ///   - offeringIdentifier: Explicit RevenueCat offering identifier. When omitted, `state.requestedReason` is used as a RevenueCat placement. RevenueCat may return the dashboard's placement fallback offering, which can differ from the current offering; the package uses the current offering when no placement fallback is configured. An unknown explicit identifier asserts in Debug, logs a warning, and falls back.
    ///   - displayCloseButton: Whether `PaywallView` shows a close button. Defaults to `true`; when `false`, iOS sheets disable interactive dismissal, and the iOS full-screen cover and macOS sheet provide no other dismissal affordance. Pass `false` only for a hard paywall the user must purchase through.
    ///   - fonts: RevenueCatUI font provider used by the paywall.
    ///   - presentationStyle: Automatic or explicit iOS presentation style. macOS always uses a sheet.
    ///   - purchaseLogic: App-owned StoreKit 2 purchase and restore operations for `.myApp` mode. Leave `nil` when RevenueCat completes purchases.
    ///   - onEvent: Optional callback for package-owned purchase, restore, cancellation, and failure values.
    ///   - send: A closure that lifts a `PaywallAction` into your root action and dispatches it, for example `{ store.send(.paywall($0)) }`.
    /// - Returns: A view with paywall and customer-center presentation attached.
    public func revenueCatPaywall(
        state: PaywallState,
        offeringIdentifier: String? = nil,
        displayCloseButton: Bool = true,
        fonts: any PaywallFontProvider = DefaultPaywallFontProvider(),
        presentationStyle: RevenueCatPaywallPresentationStyle = .automatic,
        purchaseLogic: RevenueCatPaywallPurchaseLogic? = nil,
        onEvent: RevenueCatPaywallEventHandler? = nil,
        send: @escaping (PaywallAction) -> Void
    ) -> some View {
        modifier(
            RevenueCatPaywallModifier(
                state: state,
                offeringIdentifier: offeringIdentifier,
                displayCloseButton: displayCloseButton,
                fonts: fonts,
                presentationStyle: presentationStyle,
                purchaseLogic: purchaseLogic,
                onEvent: onEvent,
                send: send
            )
        )
    }
}
