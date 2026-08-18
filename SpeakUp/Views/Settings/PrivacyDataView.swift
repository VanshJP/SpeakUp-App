import SwiftUI

/// Storage and model disclosure, deletion, and the legal links, in the app and
/// in the same words as the store listing.
///
/// Answers collapse rather than sitting open: a screen of open paragraphs is a
/// document, and nobody reads a document.
struct PrivacyDataView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GlassSectionHeader("Questions", icon: "questionmark.circle")

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
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
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
            question: "What does the beta cost?",
            answer: """
            Nothing. Every feature is open during the beta: unlimited scored \
            practice, all eight weeks of the curriculum, journal export, and \
            iCloud sync. There is no purchase in the app and no card involved.
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
            question: "Can I delete my data?",
            answer: """
            Yes, always. Swipe any session in History to delete it, or erase \
            every recording, goal, achievement, and lesson at once from \
            Settings, under Data Management.
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
    NavigationStack { PrivacyDataView() }
}
