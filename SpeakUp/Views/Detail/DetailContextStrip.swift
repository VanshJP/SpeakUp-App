import SwiftUI

/// What you were doing, in two lines and no card.
/// stays legible because it is the only thing here the user actually re-reads.
struct DetailContextStrip: View {
    let recording: Recording
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
