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
        case .structural: return AppColors.categoryPlum
        }
    }
}

// MARK: - Crutch Swaps Card

/// The take's crutch habits as *rehearsable lines*, not a word tally.
///
/// Every row is one habit; inside it, every distinct sentence pattern gets its
/// own before/after — the sentence exactly as it was said, then the same
/// sentence with the swap applied. That rewritten line is the product: naming
/// a fix ("cut it") asks the user to do the edit in their head, while showing
/// it hands them something they can read aloud.
///
/// One row is open at a time by default (the worst habit). Six habits' worth
/// of examples expanded at once is a wall nobody reads.
struct CrutchSwapsCard: View {
    let hits: [SessionWordHit]
    let onPlay: (TimeInterval) -> Void

    @State private var expanded: Set<String> = []
    @State private var didSeedExpansion = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                summaryLine

                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    if index > 0 {
                        MetricRowDivider()
                    }

                    hitRow(hit)
                }
            }
        }
        .onAppear(perform: seedExpansion)
    }

    // MARK: Summary

    private var totalUses: Int {
        hits.reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private var summaryLine: some View {
        if let top = hits.first {
            Text("\(totalUses) crutch words this take. Clearing \u{201C}\(top.word)\u{201D} alone removes \(top.count).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Habit row

    private func hitRow(_ hit: SessionWordHit) -> some View {
        // Grouping is cheap but not free, and `body` runs it on every redraw —
        // resolve it once per row rather than once per sub-view that wants it.
        let moments = hit.moments

        return VStack(alignment: .leading, spacing: 10) {
            header(hit, fix: moments.first?.option.replacement ?? hit.swaps.first)

            if isExpanded(hit) {
                ForEach(moments) { moment in
                    momentBlock(moment, hit: hit)
                }

                alternates(hit, moments: moments)
            }
        }
    }

    private func header(_ hit: SessionWordHit, fix: String?) -> some View {
        Button {
            toggle(hit)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\u{201C}\(hit.word)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    StatusPill(
                        text: hit.category.label,
                        color: hit.category.badgeColor,
                        fillOpacity: 0.2
                    )

                    Spacer(minLength: 4)

                    Text("\(hit.count)\u{00D7}")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hit.category.badgeColor)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded(hit) ? 0 : -90))
                }

                // Collapsed rows still answer "so what do I do?".
                if !isExpanded(hit), let fix {
                    Label(fix, systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibility(hit, fix: fix))
        .accessibilityHint(isExpanded(hit) ? "Collapse this habit" : "Expand for examples and fixes")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: One teachable moment

    @ViewBuilder
    private func momentBlock(_ moment: WordSwapMoment, hit: SessionWordHit) -> some View {
        if let example = moment.example, example.fragment.contains(where: \.isTarget) {
            VStack(alignment: .leading, spacing: 8) {
                // The before/after reads as one sentence pair, so VoiceOver
                // gets one spoken comparison instead of a word-by-word crawl.
                VStack(alignment: .leading, spacing: 8) {
                    labelled("You said") {
                        spokenLine(
                            example.fragment,
                            tint: hit.category.badgeColor,
                            strikeTarget: moment.option.edit.isMechanical
                        )
                    }

                    if let rewritten = example.rewritten {
                        labelled("Say this") {
                            rewrittenLine(rewritten)
                        }
                    } else {
                        labelled("Try instead") {
                            Text(moment.option.replacement)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                        }
                    }

                    if let cue = moment.option.cue {
                        Text(cue)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(momentAccessibility(moment))

                playRow(moment, hit: hit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Play points

    /// Stamps stay playable but never print a clock time — Whisper word
    /// timings drift enough that a wrong "0:37" reads as a broken app while a
    /// wrong seek just plays nearby audio (recording-detail invariant 17).
    /// Unusable zero starts get no button at all (invariant 18).
    @ViewBuilder
    private func playRow(_ moment: WordSwapMoment, hit: SessionWordHit) -> some View {
        let playable = Array(moment.playable.prefix(6))

        if !playable.isEmpty {
            HStack(spacing: 6) {
                Text("Hear it")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(playable.enumerated()), id: \.element.id) { index, occurrence in
                    Button {
                        onPlay(occurrence.timestamp)
                    } label: {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(hit.category.badgeColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(hit.category.badgeColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(hit.word), occurrence \(index + 1) of \(playable.count)")
                }
            }
        }
    }

    // MARK: Alternates

    /// Advice that did not win, rendered as flat text pills. They must not
    /// borrow the filled-capsule look of the play buttons beside them — the
    /// old card styled un-tappable suggestions exactly like tappable stamps.
    @ViewBuilder
    private func alternates(_ hit: SessionWordHit, moments: [WordSwapMoment]) -> some View {
        let shown = Set(moments.map(\.option.replacement))
        let options = hit.swaps.filter { !shown.contains($0) }

        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also works")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Text(option)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.06)))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Also works: \(options.joined(separator: ", "))")
        }
    }

    // MARK: Fragment rendering

    private func spokenLine(_ pieces: [FragmentPiece], tint: Color, strikeTarget: Bool) -> Text {
        pieces.enumerated().reduce(Text("")) { accumulated, item in
            accumulated + spokenSpan(
                item.element,
                tint: tint,
                strike: strikeTarget,
                trailingSpace: item.offset < pieces.count - 1
            )
        }
    }

    private func spokenSpan(_ piece: FragmentPiece, tint: Color, strike: Bool, trailingSpace: Bool) -> Text {
        let gap = trailingSpace ? Text(" ").font(.caption) : Text("")

        if piece.isTarget {
            let word = Text(piece.text).font(.caption.weight(.semibold)).foregroundStyle(tint)
            return (strike ? word.strikethrough(true, color: tint.opacity(0.8)) : word) + gap
        }
        if piece.text == "\u{2026}" {
            return Text(piece.text).font(.caption).italic().foregroundStyle(.tertiary) + gap
        }
        return Text(piece.text).font(.caption).foregroundStyle(.secondary) + gap
    }

    /// The corrected line reads as the recommendation: full-strength text with
    /// any swapped-in words in success green.
    private func rewrittenLine(_ pieces: [FragmentPiece]) -> Text {
        pieces.enumerated().reduce(Text("")) { accumulated, item in
            let piece = item.element
            let gap = item.offset < pieces.count - 1 ? Text(" ").font(.caption) : Text("")

            if piece.isTarget {
                return accumulated
                    + Text(piece.text).font(.caption.weight(.bold)).foregroundStyle(AppColors.success)
                    + gap
            }
            if piece.text == "\u{2026}" {
                return accumulated + Text(piece.text).font(.caption).italic().foregroundStyle(.tertiary) + gap
            }
            return accumulated + Text(piece.text).font(.caption).foregroundStyle(.primary) + gap
        }
    }

    // MARK: Expansion

    private func isExpanded(_ hit: SessionWordHit) -> Bool {
        expanded.contains(hit.id)
    }

    private func toggle(_ hit: SessionWordHit) {
        Haptics.light()
        withAnimation(AppMotion.snap) {
            if expanded.contains(hit.id) {
                expanded.remove(hit.id)
            } else {
                expanded.insert(hit.id)
            }
        }
    }

    /// Worst habit open, the rest collapsed — the card lands as one lesson
    /// plus a list, not six essays.
    private func seedExpansion() {
        guard !didSeedExpansion, let first = hits.first else { return }
        didSeedExpansion = true
        expanded = [first.id]
    }

    // MARK: Accessibility

    private func headerAccessibility(_ hit: SessionWordHit, fix: String?) -> String {
        var label = "\(hit.word), \(hit.category.label), \(hit.count) times"
        if !isExpanded(hit), let fix {
            label += ". Fix: \(fix)"
        }
        return label
    }

    private func momentAccessibility(_ moment: WordSwapMoment) -> String {
        guard let example = moment.example else { return "" }

        var label = "You said: \(example.fragment.map(\.text).joined(separator: " "))."
        if let rewritten = example.rewritten {
            label += " Say this: \(rewritten.map(\.text).joined(separator: " "))."
        } else {
            label += " Try instead: \(moment.option.replacement)."
        }
        if let cue = moment.option.cue {
            label += " \(cue)."
        }
        if moment.count > 1 {
            label += " \(moment.count) occurrences share this fix."
        }
        return label
    }

    // MARK: Data

    /// The take's worst habits, ready to render: two-plus occurrences, ranked,
    /// capped at six rows. A one-off word is not a habit worth coaching.
    /// Takes the already-resolved words — the caller's `transcriptionWords`
    /// access decodes a blob, so it must happen once in setup, not per render.
    static func hits(from words: [TranscriptionWord]?) -> [SessionWordHit] {
        guard let words, !words.isEmpty else { return [] }

        return Array(
            LexiconInsightsEngine.sessionHits(from: words)
                .filter { $0.count >= 2 }
                .prefix(6)
        )
    }
}
