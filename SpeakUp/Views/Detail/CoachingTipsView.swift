import SwiftUI

struct CoachingTipsView: View {
    var plan: CoachPlan?
    let tips: [CoachingTip]
    var onPractice: ((CoachPracticeRoute) -> Void)?
    var onPlayFrom: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan {
                CoachFocusCard(plan: plan)
            }

            GlassSectionHeader(plan == nil ? "Coaching" : "This session")

            // One plate with inset hairlines, not a tinted card per tip: every
            // tip at tint 0.10 turned the tab into a highlighter. A tip's
            // colour lives on its glyph.
            if !tips.isEmpty {
                GlassRowGroup(dividerInset: CoachingTipRow.textInset) {
                    ForEach(tips) { tip in
                        CoachingTipRow(tip: tip, onPractice: onPractice, onPlayFrom: onPlayFrom)
                    }
                }
            }
        }
    }
}

// MARK: - Tip Row

private struct CoachingTipRow: View {
    let tip: CoachingTip
    var onPractice: ((CoachPracticeRoute) -> Void)?
    var onPlayFrom: ((TimeInterval) -> Void)?

    @State private var isExpanded = false

    /// Where the text column starts: row padding, glyph, gap. The group's
    /// hairlines and the row's secondary controls line up on it.
    static let textInset: CGFloat = horizontalPadding + chipSize + 12
    private static let horizontalPadding: CGFloat = 14
    private static let chipSize: CGFloat = 32

    private var hasTeachingPoint: Bool { !tip.teachingPoint.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
                Haptics.light()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    IconChip(icon: tip.icon, tint: tintColor, size: Self.chipSize)

                    VStack(alignment: .leading, spacing: 4) {
                        if let eyebrow {
                            Text(eyebrow)
                                .eyebrowStyle(tintColor)
                        }

                        Text(tip.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(tip.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if hasTeachingPoint {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.spring(response: 0.3), value: isExpanded)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(!hasTeachingPoint)
            .accessibilityLabel([eyebrow, tip.title, tip.message].compactMap { $0 }.joined(separator: ". "))
            .accessibilityValue(
                hasTeachingPoint
                    ? (isExpanded ? "Expanded" : "Collapsed")
                    : "No additional detail"
            )
            .accessibilityHint(hasTeachingPoint ? "Shows the teaching point" : "")

            if let time = tip.evidenceTime, let onPlayFrom {
                Button {
                    onPlayFrom(time)
                } label: {
                    pill(icon: "play.circle.fill", title: "Hear it", fillOpacity: 0.22)
                }
                .buttonStyle(GlassPressStyle())
                .padding(.leading, Self.textInset)
                // The pill's 44pt target overhangs the row padding above it.
                .padding(.top, -8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Hear the moment this tip points at")
            }

            if isExpanded, hasTeachingPoint {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(height: 0.5)

                    Text(tip.teachingPoint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    if let route = tip.suggestedPractice, let title = route.actionTitle {
                        Button {
                            Haptics.medium()
                            onPractice?(route)
                        } label: {
                            pill(icon: route.display?.icon, title: title, fillOpacity: 0.15)
                        }
                        .buttonStyle(GlassPressStyle())
                        .disabled(onPractice == nil)
                        .accessibilityLabel(title)
                        .accessibilityHint(onPractice == nil ? "Not available" : "")
                    }
                }
                .padding(.leading, Self.textInset)
                .padding(.trailing, Self.horizontalPadding)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A small tinted capsule inside a 44pt target: the pill reads as a chip,
    /// the finger gets a full-size button.
    private func pill(icon: String?, title: String, fillOpacity: Double) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tintColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(tintColor.opacity(fillOpacity), in: Capsule())
        .frame(minHeight: AppLayout.minHitTarget)
        .contentShape(Rectangle())
    }

    private var eyebrow: String? {
        switch tip.kind {
        case .focus: return "Focus"
        case .win: return "Working"
        case .signal: return "About this recording"
        case .supporting: return nil
        }
    }

    private var tintColor: Color {
        switch tip.kind {
        case .win: return AppColors.success
        case .signal: return AppColors.categoryNeutralCool
        case .focus, .supporting: return tip.dimension.map { AppColors.tint(for: $0) } ?? AppColors.primary
        }
    }
}
