import SwiftUI

struct CoachingTipsView: View {
    let tips: [CoachingTip]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coaching Tips", systemImage: "lightbulb.fill")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(tips) { tip in
                    CoachingTipRow(tip: tip)
                }
            }
        }
    }
}

private struct CoachingTipRow: View {
    let tip: CoachingTip
    @State private var isExpanded = false

    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 28

    var body: some View {
        GlassCard(tint: tintColor.opacity(0.1), padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // Main tip content
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
                            Text(tip.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            Text(tip.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if tip.teachingPoint != nil {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.spring(response: 0.3), value: isExpanded)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(tip.teachingPoint == nil)

                // Expandable teaching point
                if isExpanded, let teachingPoint = tip.teachingPoint {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle()
                            .fill(.white.opacity(0.1))
                            .frame(height: 0.5)

                        Text(teachingPoint)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)

                        if let drillMode = tip.suggestedDrillMode {
                            HStack(spacing: 6) {
                                Image(systemName: drillIcon(for: drillMode))
                                    .font(.caption2)
                                Text("Try \(drillName(for: drillMode))")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(tintColor)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(tintColor.opacity(0.15))
                            .clipShape(Capsule())
                            .accessibilityLabel("Suggested drill: \(drillName(for: drillMode))")
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var tintColor: Color {
        switch tip.category {
        case .pace: return .blue
        case .fillers: return .orange
        case .pauses: return .purple
        case .clarity: return .teal
        case .delivery: return .cyan
        case .relevance: return .indigo
        case .encouragement: return .green
        }
    }

    private func drillName(for mode: String) -> String {
        switch mode {
        case "fillerElimination": return "Filler Elimination"
        case "paceControl": return "Pace Control"
        case "pausePractice": return "Pause Practice"
        case "impromptuSprint": return "Impromptu Sprint"
        default: return "Drill"
        }
    }

    private func drillIcon(for mode: String) -> String {
        switch mode {
        case "fillerElimination": return "xmark.circle"
        case "paceControl": return "speedometer"
        case "pausePractice": return "pause.circle"
        case "impromptuSprint": return "bolt.fill"
        default: return "figure.run"
        }
    }
}
