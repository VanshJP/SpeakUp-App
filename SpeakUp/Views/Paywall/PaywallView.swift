import StoreKit
import SwiftData
import SwiftUI

/// The one purchase decision in the app.
///
/// Presented full screen, and paced as a short flow rather than a single sheet:
/// what the user has already moved, what is still on the table and how slowly
/// the free tier gets there, then the offer. Each step is built only from the
/// user's own recordings — the strongest argument for keeping a practice tool is
/// the practice already in it.
///
/// A user with nothing scored yet sees only the offer. An empty progress screen
/// in front of a price is a toll booth, and the price is never more than one tap
/// away from any step. The ownership scope stays in the FAQ rather than sitting
/// between the user and the price — same words there, on the store listing, and
/// on the support site.
struct PaywallView: View {
    let request: PaywallRequest

    /// The steps ahead of the offer. Only ever grown by data the user produced.
    private enum Step: Hashable {
        case progress
        case headroom
        case offer
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var purchases: PurchaseService { PurchaseService.shared }
    private var entitlements: EntitlementStore { EntitlementStore.shared }

    @State private var showingFAQ = false
    @State private var showingRedeemCode = false
    @State private var didSucceed = false
    /// The user's own practice. Resolved once off the main thread — decoding
    /// `Recording.analysis` in `body` would run on every redraw of a scrolling
    /// sheet.
    @State private var proof = PaywallProof()
    @State private var heroAppeared = false
    @State private var step: Step = .offer

    /// Only the steps this user's own library can fill.
    private var steps: [Step] {
        guard proof.hasScores else { return [.offer] }
        guard proof.headroom != nil else { return [.progress, .offer] }
        return [.progress, .headroom, .offer]
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            if didSucceed {
                successState
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                flow
                    .transition(.opacity)
            }
        }
        .animation(AppMotion.settle, value: didSucceed)
        // Above the paged content and its swipe area. Without the zIndex the
        // TabView page takes the hit test at the top edge and Close/Restore go
        // dead even though they are drawn on top.
        .overlay(alignment: .top) { topBar.zIndex(1) }
        .sheet(isPresented: $showingFAQ) {
            NavigationStack { LifetimeFAQView() }
        }
        .offerCodeRedemption(isPresented: $showingRedeemCode) { result in
            Task {
                if case .success = result {
                    await purchases.refreshEntitlement()
                    AnalyticsService.shared.log(.restoreResult("offer_code"))
                }
                if entitlements.isLifetime { didSucceed = true }
            }
        }
        .task {
            // A cancelled or failed attempt from a previous presentation would
            // otherwise greet the next one with a stale red line.
            purchases.clearPhase()
            withAnimation(AppMotion.settle) { heroAppeared = true }
            proof = await PaywallProof.load(container: modelContext.container)
            // Start on the first step the loaded data can actually fill. Set
            // after the load rather than before, so a user with an empty library
            // never sees a personalised step flash and disappear.
            if let first = steps.first { step = first }
            await purchases.loadProduct()
            markPaywallSeen()
        }
        .onChange(of: entitlements.isLifetime) { _, owned in
            if owned { didSucceed = true }
        }
        .onChange(of: didSucceed) { _, succeeded in
            guard succeeded else { return }
            Haptics.success()
            Task {
                // Long enough to read the confirmation. A purchase that flashes
                // past leaves the user unsure anything happened.
                try? await Task.sleep(for: .milliseconds(1600))
                dismiss()
            }
        }
    }

    // MARK: - Flow

    private var flow: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                ForEach(steps, id: \.self) { step in
                    page(for: step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppMotion.slide, value: step)

            if steps.count > 1 { stepDots }

            bottomBar
        }
        .padding(.top, 52)
    }

    @ViewBuilder
    private func page(for step: Step) -> some View {
        switch step {
        case .progress:
            PaywallProgressStep(proof: proof)
        case .headroom:
            if let headroom = proof.headroom {
                PaywallHeadroomStep(proof: proof, headroom: headroom)
            }
        case .offer:
            offer
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { dot in
                Circle()
                    .fill(dot == step ? AppColors.primary : Color.white.opacity(0.22))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    /// Advance, or buy. The price is one tap from every step and never hidden
    /// behind the story — a flow the user cannot skip is a toll booth.
    @ViewBuilder
    private var bottomBar: some View {
        switch step {
        case .offer:
            buyBar
        case .progress, .headroom:
            VStack(spacing: 10) {
                GlassButton(
                    title: step == .progress ? "What's still on the table" : "See what Lifetime unlocks",
                    style: .primary,
                    size: .large,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    advance()
                }

                Button("Skip to the offer") {
                    Haptics.light()
                    withAnimation(AppMotion.slide) { step = .offer }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        withAnimation(AppMotion.slide) { step = steps[index + 1] }
    }

    // MARK: - Offer

    private var offer: some View {
        PageScrollView {
            VStack(spacing: 20) {
                hero
                headline
                includedCard
                priceCard
            }
            .padding(.horizontal, 20)
            // The hero's 190pt glow overflows its 116pt frame by ~37pt a side,
            // and a ScrollView clips to its content bounds — without the inset
            // the glow gets sliced flat across the top.
            .padding(.top, 40)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(AppColors.cardStroke, lineWidth: 0.5))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Close")

            Spacer()

            // Restore belongs in the chrome, not in the body: the person who
            // needs it already owns this and should not have to read the pitch.
            if !didSucceed {
                Button {
                    Haptics.light()
                    Task { await restore() }
                } label: {
                    Group {
                        if purchases.phase == .restoring {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Restore")
                        }
                    }
                    // Same glass chip as Close. Bare text floating over a
                    // scrolling page reads as part of the page.
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5))
                }
                .buttonStyle(GlassPressStyle())
                .disabled(purchases.isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(0.40), AppColors.primary.opacity(0)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 92
                    )
                )
                .frame(width: 190, height: 190)
                .blur(radius: 14)

            Image("BigTalkOrb")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        }
        .frame(height: 116)
        .scaleEffect(heroAppeared ? 1 : 0.86)
        .opacity(heroAppeared ? 1 : 0)
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text(headlineTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(request.feature.paywallReason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The concrete thing at stake outranks the pitch. Takes the user already
    /// recorded and cannot see scored is a fact about their library, not a
    /// scare line, so it leads when there is one.
    private var headlineTitle: String {
        switch proof.deferred {
        case 0: return "Keep the whole gym."
        case 1: return "1 take is waiting to be scored."
        default: return "\(proof.deferred) takes are waiting to be scored."
        }
    }

    // MARK: - What's included

    private var includedCard: some View {
        GlassCard(cornerRadius: 20, tint: AppColors.glassTintPrimary, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.includedRows, id: \.title) { row in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppColors.primary.opacity(0.16))
                                .frame(width: 32, height: 32)
                            Image(systemName: row.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                }

                // The free offer stated on the screen that sells the paid one:
                // finding out what you already had only after it lapses is the
                // version that feels like a trick.
                Text(Self.freeOfferText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One wording for the free offer, shared with the FAQ and the store
    /// listing. Says "free for 14 days" and never "trial period" — this is a
    /// time-limited free tier ahead of a one-time purchase, not an
    /// auto-renewing subscription trial, and App Review reads those differently.
    static let freeOfferText = """
    Everything except iCloud sync is free for your first 14 days, starting at \
    your first score. After that, three full analyses every 30 days. Nothing \
    charges by itself, ever.
    """

    private struct IncludedRow {
        let icon: String
        let title: String
        let detail: String
    }

    private static let includedRows: [IncludedRow] = [
        IncludedRow(
            icon: "infinity",
            title: "Unlimited scored practice",
            detail: "Record and analyze as often as you want, on device."
        ),
        IncludedRow(
            icon: "book.closed",
            title: "The full eight-week curriculum",
            detail: "Every phase past the first, with lessons that respond to your own sessions."
        ),
        IncludedRow(
            icon: "icloud",
            title: "iCloud sync",
            detail: "Your practice on every device, in your own iCloud account."
        ),
        IncludedRow(
            icon: "square.and.arrow.down",
            title: "Journal export",
            detail: "Your sessions, scores, and notes as a PDF you keep."
        ),
        IncludedRow(
            icon: "gift",
            title: "Every future feature",
            detail: "Whatever we add later is yours too. You are never asked to pay again."
        )
    ]

    // MARK: - Price

    /// The price gets its own surface rather than living inside a button label.
    /// A one-time purchase competing with a market of subscriptions has exactly
    /// one advantage, and it has to be legible at a glance.
    private var priceCard: some View {
        GlassCard(
            cornerRadius: 20,
            tint: AppColors.primary,
            padding: 16,
            accentBorder: AppColors.primary
        ) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Lifetime")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if FoundingOffer.isActive() {
                            Text("FOUNDING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(AppColors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(AppColors.warning.opacity(0.16))
                                )
                        }
                    }

                    Text("One payment. No subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if let price = purchases.displayPrice {
                        Text(price)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        // StoreKit has not priced this storefront yet. A
                        // placeholder is honest; a hardcoded number is not.
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppColors.meterTrack)
                            .frame(width: 76, height: 26)
                            .shimmer()
                    }

                    if let after = FoundingOffer.comparisonPrice(currencyCode: purchases.currencyCode) {
                        (Text(after).strikethrough(true, color: .secondary) + Text(" after"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Buy bar

    /// Pinned. The decision and the button that resolves it must not be separated
    /// by a scroll position.
    private var buyBar: some View {
        VStack(spacing: 10) {
            if purchases.phase == .pendingApproval {
                statusLine(
                    icon: "clock",
                    text: "Waiting for approval. Big Talk unlocks by itself once it goes through.",
                    color: AppColors.info
                )
            }

            if let message = purchases.errorMessage {
                statusLine(icon: "exclamationmark.triangle", text: message, color: AppColors.error)
            }

            GlassButton(
                title: buyButtonTitle,
                style: .primary,
                size: .large,
                isLoading: purchases.phase == .purchasing || purchases.loadState == .loading,
                fullWidth: true
            ) {
                Haptics.medium()
                Task { await buy() }
            }
            // Restoring counts as busy: tapping Buy mid-restore would start a
            // second StoreKit flow for something the user may already own.
            // A failed product load stays tappable on purpose — `purchase()`
            // retries the load, so the retry is the same button rather than a
            // dead end the user can only escape by closing the sheet.
            .disabled(purchases.isBusy || purchases.loadState == .loading)

            Text("Tied to your Apple Account and restores on any device you sign in to.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            footerLinks
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background {
            // Fades the scroll into the bar instead of cutting it with a seam.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    /// The price already has a card. Repeating it here only makes the button
    /// longer, and it reads as two prices on a storefront with a long currency
    /// string.
    private var buyButtonTitle: String {
        if case .failed = purchases.loadState, !purchases.canPurchase {
            return "Try again"
        }
        return "Unlock Lifetime"
    }

    private func statusLine(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4)
    }

    private var footerLinks: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button("What's included") {
                    Haptics.light()
                    showingFAQ = true
                }
                separatorDot
                Button("Redeem code") {
                    Haptics.light()
                    showingRedeemCode = true
                }
            }

            // Terms and privacy, reachable from the screen that takes the money.
            // Hidden entirely until the site exists rather than shipping dead
            // links — `RELEASE_CHECKLIST.md` covers filling the Info.plist keys.
            if SupportLinks.hasAnyWebDestination {
                HStack(spacing: 10) {
                    if let terms = SupportLinks.terms {
                        Link("Terms", destination: terms)
                    }
                    if let privacy = SupportLinks.privacyPolicy {
                        if SupportLinks.terms != nil { separatorDot }
                        Link("Privacy", destination: privacy)
                    }
                    if let support = SupportLinks.support {
                        if SupportLinks.terms != nil || SupportLinks.privacyPolicy != nil { separatorDot }
                        Link("Support", destination: support)
                    }
                }
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var separatorDot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 2.5, height: 2.5)
    }

    // MARK: - Success

    private var successState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.success.opacity(0.35), AppColors.success.opacity(0)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 100
                        )
                    )
                    .frame(width: 210, height: 210)
                    .blur(radius: 16)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(AppColors.success)
            }

            Text("You own Big Talk.")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Everything is unlocked on this Apple Account, on every device, including whatever we add later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // True as written: `ContentView` resumes deferred recordings the
            // moment entitlement flips.
            if proof.deferred > 0 {
                Text(proof.deferred == 1
                     ? "Scoring the take that was waiting."
                     : "Scoring the \(proof.deferred) takes that were waiting.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
    }

    // MARK: - Ownership scope

    /// Kept identical to the App Store description, the FAQ, and the support
    /// site. A purchase scope that reads differently in three places is how
    /// refund requests start. It is surfaced through `LifetimeFAQView`, one tap
    /// from the buy bar, rather than between the user and the price.
    ///
    /// Deliberately unqualified: one purchase, every feature, including the ones
    /// that do not exist yet. There is no carve-out for future add-ons, because
    /// a carve-out is what makes the word "lifetime" mean nothing. Anything the
    /// app gains later ships to existing owners at no charge.
    static let ownershipScopeText = """
    Pay once and Big Talk is yours. Everything in the app today and everything \
    added later is included, at no extra charge. No subscription, no upgrade \
    fee, no second purchase, ever.
    """

    // MARK: - Actions

    private func buy() async {
        let succeeded = await purchases.purchase()
        let result: String
        switch purchases.phase {
        case .purchased: result = "purchased"
        case .cancelled: result = "cancelled"
        case .pendingApproval: result = "pending"
        case .failed: result = "failed"
        default: result = succeeded ? "purchased" : "unknown"
        }
        AnalyticsService.shared.log(
            .purchaseResult(result, price: purchases.displayPrice, source: AttributionStore.shared.source)
        )
        if succeeded { didSucceed = true }
    }

    private func restore() async {
        let restored = await purchases.restore()
        AnalyticsService.shared.log(.restoreResult(restored ? "restored" : "nothing_to_restore"))
        if restored { didSucceed = true }
    }

    private func markPaywallSeen() {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        guard let settings = try? modelContext.fetch(descriptor).first, !settings.hasSeenPaywall else { return }
        settings.hasSeenPaywall = true
        try? modelContext.save()
    }
}

#Preview {
    PaywallView(request: PaywallRequest(feature: .unlimitedAnalyses, trigger: "preview"))
        .modelContainer(for: [UserSettings.self, Recording.self, Prompt.self], inMemory: true)
}
