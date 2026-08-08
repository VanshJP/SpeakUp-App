import SwiftUI

/// What you were doing, in two lines and no card.
///
/// This is metadata, not content — giving it a glass surface of its own made it
/// compete with the score for the top of the page. Category, date, time,
/// duration, and difficulty collapse into one caption line; the prompt itself
/// stays legible because it is the only thing here the user actually re-reads.
///
/// Shared by `RecordingDetailView` and the analyzing skeleton so the header does
/// not move, restyle, or re-wrap the moment the score lands: everything it shows
/// is known before analysis starts.
struct DetailContextStrip: View {
    let recording: Recording
    /// Nil while the session is still scoring — the strip renders read-only.
    var onEditTitle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: contextIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(contextMetaLine)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            if let prompt = recording.prompt {
                Text(prompt.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let onEditTitle {
                Button {
                    Haptics.light()
                    onEditTitle()
                } label: {
                    HStack(spacing: 6) {
                        titleText
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                titleText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasTitle: Bool { recording.customTitle?.isEmpty == false }

    private var titleText: some View {
        Text(hasTitle ? recording.displayTitle : "Name this session")
            .font(.title3.weight(.semibold))
            .foregroundStyle(hasTitle ? .white : .secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var contextIcon: String {
        if recording.storyId != nil { return "book.pages" }
        if let category = recording.prompt?.category {
            return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
        }
        return "waveform"
    }

    /// "Storytelling · Hard · Mar 14, 9:41 AM · 1:04"
    private var contextMetaLine: String {
        var parts: [String] = []

        if recording.storyId != nil {
            parts.append(recording.storyTitle ?? "Story Practice")
        } else if let category = recording.prompt?.category {
            parts.append(PromptCategory(rawValue: category)?.shortName ?? category)
        } else {
            parts.append("Free Practice")
        }

        if let difficulty = recording.prompt?.difficulty {
            parts.append(difficulty.displayName)
        }

        parts.append(recording.date.formatted(date: .abbreviated, time: .shortened))
        parts.append(recording.formattedDuration)

        return parts.joined(separator: " · ")
    }
}
