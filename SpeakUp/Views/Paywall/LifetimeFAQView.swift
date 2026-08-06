import SwiftUI

/// Ownership scope, free-tier boundary, storage and model disclosure, and
/// privacy — in the app, in the same words as the store listing.
///
/// This exists in-app rather than only on a website because the purchase scope
/// is the thing a refund argument turns on, and a user deciding at the paywall
/// should not have to leave to read it. The scope itself sits above the fold;
/// everything else collapses, because eight open paragraphs is a document, and
/// nobody reads a document mid-purchase.
struct LifetimeFAQView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scopeCard

                    Text("QUESTIONS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                        .padding(.top, 6)
                        .padding(.leading, 4)

                    ForEach(Self.entries, id: \.question) { entry in
                        entryRow(entry)
                    }

                    legalLinks
                        .padding(.top, 8)
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

    // MARK: - Scope

    /// The one answer nobody should have to tap for.
    private var scopeCard: some View {
        GlassCard(cornerRadius: 20, tint: AppColors.primary, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
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

    private func entryRow(_ entry: Entry) -> some View {
        let isOpen = expanded.contains(entry.question)

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Haptics.light()
                    withAnimation(AppMotion.snap) {
                        if isOpen {
                            expanded.remove(entry.question)
                        } else {
                            expanded.insert(entry.question)
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 0 : -90))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if isOpen {
                    Text(entry.answer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Legal

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
            question: "What can I do without paying?",
            answer: """
            Three full analyses straight away, then three per month. Every free \
            analysis is the complete result — score, subscores, transcript, and \
            your recommended next step. Everything built around those results is \
            free too: all the drills, warm-ups, and read-aloud passages, the \
            first week of the curriculum, your stories, your full history with \
            charts and the first-versus-latest replay, your goal and target pace, \
            reminders, your streak, and the cards you can share.
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
