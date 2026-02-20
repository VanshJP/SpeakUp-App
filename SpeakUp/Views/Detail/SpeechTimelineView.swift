import SwiftUI

struct SpeechTimelineView: View {
    let words: [TranscriptionWord]
    let fillerWords: [FillerWord]
    let totalDuration: TimeInterval

    private let segmentCount = 80

    private enum SegmentType {
        case speech, filler, pause

        var color: Color {
            switch self {
            case .speech: return .green
            case .filler: return .orange
            case .pause: return .gray.opacity(0.4)
            }
        }
    }

    /// End of the last spoken word — used to trim trailing dead air
    private var speechEnd: TimeInterval {
        words.last?.end ?? totalDuration
    }

    private var segments: [SegmentType] {
        guard totalDuration > 0, !words.isEmpty else {
            return Array(repeating: .pause, count: segmentCount)
        }

        let timelineStart: TimeInterval = 0
        let timelineEnd = speechEnd
        let timelineSpan = timelineEnd - timelineStart
        guard timelineSpan > 0 else {
            return Array(repeating: .pause, count: segmentCount)
        }

        let segmentDuration = timelineSpan / Double(segmentCount)
        var result = Array(repeating: SegmentType.pause, count: segmentCount)

        // Mark speech and filler segments from transcription words
        for word in words {
            let relStart = word.start - timelineStart
            let relEnd = word.end - timelineStart
            let startSeg = min(segmentCount - 1, max(0, Int(relStart / segmentDuration)))
            let endSeg = min(segmentCount - 1, max(0, Int(relEnd / segmentDuration)))

            for i in startSeg...endSeg {
                if word.isFiller {
                    result[i] = .filler
                } else if result[i] != .filler {
                    // Don't overwrite a filler segment with speech
                    result[i] = .speech
                }
            }
        }

        // Second pass: use fillerWords timestamps to catch any fillers
        // missed by the isFiller flag (e.g. context-dependent ones)
        for filler in fillerWords {
            for ts in filler.timestamps {
                let relTime = ts - timelineStart
                let seg = min(segmentCount - 1, max(0, Int(relTime / segmentDuration)))
                result[seg] = .filler
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speech Timeline", systemImage: "waveform.path")
                .font(.headline)

            GlassCard {
                VStack(spacing: 10) {
                    // Timeline bar
                    GeometryReader { geometry in
                        let barWidth = (geometry.size.width - CGFloat(segmentCount - 1) * 0.5) / CGFloat(segmentCount)

                        HStack(spacing: 0.5) {
                            ForEach(0..<segmentCount, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(segments[index].color)
                                    .frame(width: max(2, barWidth), height: 24)
                            }
                        }
                    }
                    .frame(height: 24)

                    // Time labels
                    HStack {
                        Text(formatTime(0))
                        Spacer()
                        Text(formatTime(speechEnd / 2))
                        Spacer()
                        Text(formatTime(speechEnd))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    // Legend
                    HStack(spacing: 16) {
                        legendItem(color: .green, label: "Speech")
                        legendItem(color: .orange, label: "Fillers")
                        legendItem(color: .gray.opacity(0.4), label: "Pauses")
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
