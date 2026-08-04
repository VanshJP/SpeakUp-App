import SwiftUI

/// Ownership scope, free-tier boundary, storage and model disclosure, and
/// privacy — in the app, in the same words as the store listing.
///
/// This exists in-app rather than only on a website because the purchase scope
/// is the thing a refund argument turns on, and a user deciding at the paywall
/// should not have to leave to read it.
struct LifetimeFAQView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.entries, id: \.question) { entry in
                        GlassCard(padding: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.question)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(entry.answer)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Lifetime & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        VStack(spacing: 10) {
            if let privacy = SupportLinks.privacyPolicy {
                linkRow("Privacy Policy", icon: "hand.raised", url: privacy)
            }
            if let terms = SupportLinks.terms {
                linkRow("Terms of Use", icon: "doc.text", url: terms)
            }
            if let support = SupportLinks.support {
                linkRow("Support", icon: "lifepreserver", url: support)
            }
            if let mail = SupportLinks.feedbackMailto {
                linkRow("Email the developer", icon: "envelope", url: mail)
            }
        }
    }

    private func linkRow(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            GlassCard(padding: 14) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 28)
            }
        }
    }

    // MARK: - Content

    private struct Entry {
        let question: String
        let answer: String
    }

    private static let entries: [Entry] = [
        Entry(
            question: "What does Lifetime include?",
            answer: PaywallView.ownershipScopeText
        ),
        Entry(
            question: "What can I do without paying?",
            answer: """
            Three full analyses straight away, then three per month. Every free \
            analysis is the complete result — score, subscores, transcript, and \
            your recommended next step. You also keep the daily prompt, a starter \
            warm-up, drill, and read-aloud passage, your goal and target pace, \
            reminders, your recent sessions, your streak, and the score card you \
            can share.
            """
        ),
        Entry(
            question: "Is this a subscription?",
            answer: """
            No. Big Talk Lifetime is a single non-consumable purchase on your \
            Apple Account. There is no renewal, and nothing you own expires.
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
            first time you practise — roughly 150 MB. The optional writing model \
            used for coherence feedback is separate and much larger (about \
            0.8-4 GB depending on your device). It is never required: skip it and \
            everything else still scores. Both live on your device and can be \
            removed in Settings.
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
            Yes, always, whether you have paid or not. Settings has per-recording \
            deletion and a full data reset. Privacy and deletion are never behind \
            the purchase.
            """
        ),
        Entry(
            question: "Does Big Talk promise a job or a promotion?",
            answer: """
            No. It measures how you speak and gives you a plan to practise. \
            Outcomes at work depend on far more than delivery, and any app \
            claiming otherwise is selling you something it cannot deliver.
            """
        )
    ]
}

#Preview {
    NavigationStack { LifetimeFAQView() }
}
