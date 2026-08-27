import SwiftUI

/// Outcome-first header for practice-tool sheets. Tells the user what the tool
/// does and when to reach for it before they hit a list of exercises.
struct ToolPurposeBanner: View {
    let tool: PracticeToolKind
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tool.color.opacity(0.18))
                    .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                Image(systemName: tool.icon)
                    .font(.system(size: compact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(tool.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.outcome)
                    .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tool.bestFor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tool.color.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tool.color.opacity(0.28), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.title). \(tool.outcome). \(tool.bestFor)")
    }
}

#Preview {
    VStack(spacing: 12) {
        ToolPurposeBanner(tool: .warmUp)
        ToolPurposeBanner(tool: .drills, compact: true)
    }
    .padding()
    .background(AppBackground())
}
