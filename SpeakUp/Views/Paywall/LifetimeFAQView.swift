import SwiftUI

/// Ownership scope, free-tier boundary, storage and model disclosure, and
/// privacy, in the app, in the same words as the store listing.
///
/// This exists in-app rather than only on a website because the purchase scope
/// is the thing a refund argument turns on, and a user deciding at the paywall
/// should not have to leave to read it. The scope itself sits above the fold;
/// everything else collapses, because a screen of open paragraphs is a document, and
/// nobody reads a document mid-purchase.
///
/// Every answer here states enforced behavior. `FreeTierPolicy.expired` is the
/// source of truth for what locks after the trial: change the policy and these
/// answers have to move with it.
struct LifetimeFAQView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scopeCard

                    GlassSectionHeader("Questions", icon: "questionmark.circle")
                        .padding(.top, 4)

                    questionsCard

                    if !Self.legalRows.isEmpty {
                        GlassSectionHeader("Legal & Support", icon: "link")
                            .padding(.top, 4)

                        legalCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .tint(.secondary)
        }
        .navigationTitle("Lifetime & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Scope

    /// The one answer nobody should have to tap for.
    private var scopeCard: some View {
        GlassCard(tint: AppColors.primary, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.body)
                        .foregroundStyle(AppColors.primary)
                    Text("What you own")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(PaywallView.ownershipScopeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Entries

    private var questionsCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 0) {
                ForEach(Array(Self.entries.enumerated()), id: \.element.question) { index, entry in
                    if index > 0 {
                        Divider().padding(.vertical, 8)
                    }

                    DisclosureGroup {
                        Text(entry.answer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Text(entry.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Legal

    private var legalCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 0) {
                ForEach(Array(Self.legalRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().padding(.vertical, 8)
                    }
                    linkRow(row.title, icon: row.icon, url: row.url)
                }
            }
        }
    }

    private func linkRow(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
    }

    // MARK: - Content

    private struct Entry {
        let question: String
        let answer: String
    }

    /// ponytail: a nil link drops out rather than rendering a dead row.
    private static var legalRows: [(title: String, icon: String, url: URL)] {
        [
            SupportLinks.privacyPolicy.map { (title: "Privacy Policy", icon: "hand.raised", url: $0) },
            SupportLinks.terms.map { (title: "Terms of Use", icon: "doc.text", url: $0) },
            SupportLinks.support.map { (title: "Support", icon: "lifepreserver", url: $0) },
            SupportLinks.feedbackMailto.map { (title: "Email the developer", icon: "envelope", url: $0) }
        ].compactMap { $0 }
    }

    private static let entries: [Entry] = [
        Entry(
            question: "What can I do without paying?",
            answer: """
            For your first 14 days, everything except iCloud sync: unlimited \
            scored practice, every week of the curriculum, and journal export \
            included. After that you keep three full analyses every 30 days, \
            and each one is the complete result, meaning score, subscores, \
            transcript, and your recommended next step.
            """
        ),
        Entry(
            question: "What stays free forever, and what locks?",
            answer: """
            Free either way: all the drills, warm-ups, and read-aloud passages, \
            your stories, your full history with charts and the \
            first-versus-latest replay, your goal and target pace, reminders, \
            your streak, week 1 of the curriculum, and the cards you can share.

            After the 14 days, three things wait behind Lifetime: the curriculum \
            past week 1, journal PDF export, and iCloud sync. Nothing you \
            already recorded is taken away.
            """
        ),
        Entry(
            question: "When do the 14 days start?",
            answer: """
            At your first completed analysis, not when you install. Days you \
            never open the app before your first score cost you nothing, and a \
            recording that fails to transcribe does not start the clock.
            """
        ),
        Entry(
            question: "What happens if I record with no analyses left?",
            answer: """
            The recording is saved and stays playable; only the scoring waits. \
            It scores itself automatically, oldest first, the moment your 30 \
            days roll over or you unlock Lifetime. Nothing is deleted and \
            nothing needs re-recording.
            """
        ),
        Entry(
            question: "Is this a subscription?",
            answer: """
            No. Big Talk Lifetime is a single non-consumable purchase on your \
            Apple Account. There is no renewal, and nothing you own expires. \
            The 14 days are a free run of the app, not a subscription trial: \
            nothing is charged when they end, and no card is involved. You \
            simply drop to three analyses every 30 days until you choose to buy.
            """
        ),
        Entry(
            question: "Will new features cost extra later?",
            answer: """
            No. One purchase covers everything in the app today and everything \
            added after you buy. No upgrade fee, no pro tier, no second \
            purchase, no feature moved behind a new price. If Big Talk gains \
            something next year, it simply appears for you.
            """
        ),
        Entry(
            question: "Where do my recordings go?",
            answer: """
            Nowhere. Audio, transcripts, and scores are created and stored on \
            this device. Nothing is uploaded to us, there is no account, and the \
            app works in airplane mode once its speech model has downloaded. \
            If you turn on iCloud sync, your data moves through your own private \
            iCloud, not through our servers.
            """
        ),
        Entry(
            question: "What gets downloaded, and how big is it?",
            answer: """
            A speech recognition model downloads once, in the background, the \
            first time you practice. It is roughly 150 MB and everything else \
            depends on it.

            The optional writing model behind coherence feedback is separate. \
            On a device with Apple Intelligence, Big Talk uses the system model \
            and downloads nothing extra. Otherwise you can choose to download \
            one yourself, from about 0.4 GB to 4 GB depending on which you pick. \
            It is never required: skip it and everything else still scores. \
            Both live on your device and can be removed in Settings.
            """
        ),
        Entry(
            question: "I already bought it. How do I get it back?",
            answer: """
            Tap Restore on the purchase screen, or in Settings. Purchases are \
            tied to your Apple Account, so any device signed in to the same \
            account can restore it. No account or password of ours is involved.
            """
        ),
        Entry(
            question: "Can I delete my data?",
            answer: """
            Yes, always, whether you have paid or not. Swipe any session in \
            History to delete it, or erase every recording, goal, achievement, \
            and lesson at once from Settings, under Data Management. Privacy and \
            deletion are never behind the purchase.
            """
        ),
        Entry(
            question: "Does Big Talk promise a job or a promotion?",
            answer: """
            No. It measures how you speak and gives you a plan to practice. \
            Outcomes at work depend on far more than delivery, and any app \
            claiming otherwise is selling you something it cannot deliver.
            """
        )
    ]
}

#Preview {
    NavigationStack { LifetimeFAQView() }
}
