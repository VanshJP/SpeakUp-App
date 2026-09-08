import SwiftUI

/// Curriculum path node states. Drawn by `LessonPathRow` + `LessonGlyphView`.
enum LessonNodeState {
    case completed
    case current
    case available
    case locked
}

struct LessonPathRow<Label: View>: View {
    let state: LessonNodeState
    let identity: LessonIdentity
    let isLeading: Bool
    let hasNext: Bool
    let nextIsLeading: Bool
    @ViewBuilder let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var nodeSize: CGFloat { 62 }
    private static var railInset: CGFloat { 35 }
    private static var connectorHeight: CGFloat { 36 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if isLeading {
                    node
                    label
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    label
                    node
                }
            }

            if hasNext {
                LessonRail(
                    fromLeading: isLeading,
                    toLeading: nextIsLeading,
                    inset: Self.railInset
                )
                .stroke(railColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(height: Self.connectorHeight)
            }
        }
    }

    private var railColor: Color {
        state == .completed ? AppColors.success.opacity(0.5) : AppColors.cardStroke
    }

    private var node: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(nodeFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(nodeStroke, lineWidth: state == .current ? 2 : 1)
                }

            if state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(nodeTint)
            } else if state == .current {
                ZStack {
                    LessonGlyphView(identity: identity, state: state)
                        .frame(width: 28, height: 28)
                        .opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(nodeTint)
                }
            } else {
                LessonGlyphView(
                    identity: identity,
                    state: state,
                    showsCheckBadge: state == .completed
                )
                .frame(width: 28, height: 28)
            }
        }
        .frame(width: Self.nodeSize, height: Self.nodeSize)
        .shadow(
            color: state == .current && !reduceMotion
                ? identity.accent.opacity(0.45)
                : .clear,
            radius: state == .current ? 14 : 0,
            y: 4
        )
        .opacity(state == .locked ? 0.55 : 1)
        .scaleEffect(state == .current && !reduceMotion ? 1.04 : 1)
    }

    private var nodeFill: Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.18)
        case .current: return identity.accent.opacity(0.22)
        case .available: return identity.accent.opacity(0.10)
        case .locked: return .white.opacity(0.05)
        }
    }

    private var nodeStroke: Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.5)
        case .current: return identity.accent
        case .available: return identity.accent.opacity(0.45)
        case .locked: return AppColors.cardStroke
        }
    }

    private var nodeTint: Color {
        switch state {
        case .completed: return AppColors.success
        case .current: return identity.accent
        case .available: return identity.accent
        case .locked: return .white.opacity(0.4)
        }
    }
}

struct LessonRail: Shape {
    let fromLeading: Bool
    let toLeading: Bool
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let startX = fromLeading ? inset : rect.maxX - inset
        let endX = toLeading ? inset : rect.maxX - inset

        var path = Path()
        path.move(to: CGPoint(x: startX, y: rect.minY))

        if startX == endX {
            path.addLine(to: CGPoint(x: endX, y: rect.maxY))
        } else {
            path.addCurve(
                to: CGPoint(x: endX, y: rect.maxY),
                control1: CGPoint(x: startX, y: rect.midY),
                control2: CGPoint(x: endX, y: rect.midY)
            )
        }
        return path
    }
}

#Preview {
    PageScrollView {
        VStack(spacing: 0) {
            LessonPathRow(
                state: .completed,
                identity: LessonIdentity.forLesson(id: "w1_l1"),
                isLeading: true,
                hasNext: true,
                nextIsLeading: false
            ) {
                Text("Your Baseline Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            LessonPathRow(
                state: .current,
                identity: LessonIdentity.forLesson(id: "w1_l3"),
                isLeading: false,
                hasNext: true,
                nextIsLeading: true
            ) {
                Text("Understanding Pace")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            LessonPathRow(
                state: .locked,
                identity: LessonIdentity.forLesson(id: "w1_l4"),
                isLeading: true,
                hasNext: false,
                nextIsLeading: false
            ) {
                Text("Reading Your Score")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .background(AppBackground())
}
