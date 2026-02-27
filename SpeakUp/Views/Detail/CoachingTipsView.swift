import SwiftUI

struct CoachingTipsView: View {
    let tips: [CoachingTip]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching Tips")
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

    var body: some View {
        GlassCard(tint: tintColor.opacity(0.1), padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tip.icon)
                    .font(.title3)
                    .foregroundStyle(tintColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title)
                        .font(.subheadline.weight(.semibold))

                    Text(tip.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
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
}
