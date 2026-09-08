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

            Label(plan == nil ? "Coaching" : "This Session", systemImage: "lightbulb.fill")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(tips) { tip in
                    CoachingTipRow(tip: tip, onPractice: onPractice, onPlayFrom: onPlayFrom)
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

    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 28
    private var hasTeachingPoint: Bool { !tip.teachingPoint.isEmpty }

    var body: some View {
        GlassCard(tint: tintColor.opacity(tip.kind == .signal ? 0.04 : 0.1), padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                    Haptics.light()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(tintColor)
                            .frame(width: iconWidth)

                        VStack(alignment: .leading, spacing: 4) {
                            if let eyebrow {
                                Text(eyebrow)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(tintColor)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
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
                }
                .buttonStyle(.plain)
                .disabled(!hasTeachingPoint)
                .accessibilityLabel(tip.title)
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
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption2)
                            Text("Hear it")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(tintColor)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(tintColor.opacity(0.22))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
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

                        if let route = tip.suggestedPractice, let label = route.display {
                            Button {
                                Haptics.medium()
                                onPractice?(route)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: label.icon)
                                        .font(.caption2)
                                    Text("Try \(label.title)")
                                        .font(.caption.weight(.medium))
                                }
                                .foregroundStyle(tintColor)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(tintColor.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(onPractice == nil)
                            .accessibilityLabel("Start \(label.title)")
                            .accessibilityHint(onPractice == nil ? "Not available" : "")
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
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
