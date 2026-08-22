import SwiftUI

// MARK: - Category badge palette

extension CrutchCategory {
    /// Shared identity-badge tint across the Words tab and session cards.
    var badgeColor: Color {
        switch self {
        case .filler: return AppColors.warning
        case .hedge: return AppColors.categoryIndigo
        case .intensifier: return AppColors.categoryCopper
        case .vague: return AppColors.categoryTeal
        }
    }
}

// MARK: - Crutch Swaps Card

/// The per-session version of the Words tab: every crutch word this take used,
/// where it happened (playable), and what to say instead — grounded in one
/// real sentence from the take, not generic advice.
///
/// Sits beside the Filler Words section on the transcript tab — fillers show
/// the what-and-where, this card adds the so-what.
struct CrutchSwapsCard: View {
    let hits: [SessionWordHit]
    let onPlay: (TimeInterval) -> Void

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    if index > 0 {
                        MetricRowDivider()
                    }

                    hitRow(hit)
                }
            }
        }
    }

    private func hitRow(_ hit: SessionWordHit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\u{201C}\(hit.word)\u{201D}")
                    .font(.subheadline)

                StatusPill(
                    text: hit.category.label,
                    color: hit.category.badgeColor,
                    fillOpacity: 0.2
                )

                Spacer()

                Text("\(hit.count)\u{00D7}")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hit.category.badgeColor)
            }
            .accessibilityElement(children: .combine)

            if !hit.timestamps.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(hit.timestamps.prefix(12).enumerated()), id: \.offset) { _, stamp in
                        Button {
                            onPlay(stamp)
                        } label: {
                            Text(CoachEvidence.stamp(stamp))
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(hit.category.badgeColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(hit.category.badgeColor.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(hit.word) at \(CoachEvidence.stamp(stamp))")
                    }
                }
            }

            if let fragment = hit.exampleFragment, fragment.contains(where: \.isTarget) {
                exampleBlock(fragment, tint: hit.category.badgeColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Example sentence: \(fragment.map(\.text).joined(separator: " "))")
            }

            if !hit.swaps.isEmpty {
                swapsBlock(hit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(swapsAccessibility(hit))
            }
        }
    }

    // MARK: Context fragment

    /// The actual sentence around the strongest occurrence; the crutch word
    /// is tinted so the eye lands on what triggered the advice.
    private func exampleBlock(_ fragment: [FragmentPiece], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("In context")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            fragment.enumerated().reduce(Text("")) { accumulated, item in
                accumulated + styledFragmentSpan(item.element, tint: tint, trailingSpace: item.offset < fragment.count - 1)
            }
        }
    }

    private func styledFragmentSpan(_ piece: FragmentPiece, tint: Color, trailingSpace: Bool) -> Text {
        let content = piece.text + (trailingSpace ? " " : "")
        if piece.isTarget {
            return Text(content).font(.caption.weight(.semibold)).foregroundStyle(tint)
        }
        if piece.text == "\u{2026}" {
            return Text(content).font(.caption).italic().foregroundStyle(.tertiary)
        }
        return Text(content).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Swaps

    private func swapsBlock(_ hit: SessionWordHit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try instead")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(Array(hit.swaps.enumerated()), id: \.offset) { index, swap in
                    swapChip(swap, isPrimary: index == 0 && hit.primarySwap != nil)
                }
            }

            if let cue = hit.primarySwap?.cue {
                Text(cue)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func swapChip(_ label: String, isPrimary: Bool) -> some View {
        Text(label)
            .font(isPrimary ? .caption.weight(.semibold) : .caption2.weight(.medium))
            .foregroundStyle(AppColors.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppColors.primary.opacity(isPrimary ? 0.22 : 0.13)))
            .overlay {
                if isPrimary {
                    Capsule().strokeBorder(AppColors.primary.opacity(0.45), lineWidth: 1)
                }
            }
    }

    // MARK: Accessibility

    private func swapsAccessibility(_ hit: SessionWordHit) -> String {
        var label = "Try instead: \(hit.swaps[0])"
        if let cue = hit.primarySwap?.cue {
            label += " — \(cue)"
        }
        let alternates = hit.swaps.dropFirst()
        if !alternates.isEmpty {
            label += ". Alternatives: \(alternates.joined(separator: ", "))."
        }
        return label
    }

    // MARK: Data

    /// The take's worst habits, ready to render: two-plus occurrences, ranked,
    /// capped at six rows. A one-off word is not a habit worth coaching.
    static func hits(for recording: Recording) -> [SessionWordHit] {
        guard let words = recording.transcriptionWords, !words.isEmpty else { return [] }

        return Array(
            LexiconInsightsEngine.sessionHits(from: words)
                .filter { $0.count >= 2 }
                .prefix(6)
        )
    }
}
