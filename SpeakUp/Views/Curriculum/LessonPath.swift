import SwiftUI

/// The curriculum as a path rather than a list.
///
/// A flat column of identical rows gives no sense of route — where you started,
/// how far in you are, what's still gated. Alternating the node side and
/// running a rail between nodes makes progression the thing you see first, and
/// the rail's color carries state: solid up to where you've been, faded past it.
///
/// Titles stay beside each node deliberately. A pure icon path reads well when
/// every unit is interchangeable practice; here the lesson names carry real
/// information, and dropping them to chase the look would trade usability for
/// style.
/// Top-level rather than nested in `LessonPathRow`: nesting it inside a
/// generic would force every mention to spell out a `Label` type it has
/// nothing to do with.
enum LessonNodeState {
    case completed
    case current
    case available
    case locked
}

struct LessonPathRow<Label: View>: View {
    let state: LessonNodeState
    let icon: String
    /// Nodes alternate sides down the scroll; the rail follows.
    let isLeading: Bool
    /// False on the last row, which has nothing to connect to.
    let hasNext: Bool
    let nextIsLeading: Bool
    @ViewBuilder let label: Label

    private static var nodeSize: CGFloat { 58 }
    private static var railInset: CGFloat { 33 }
    private static var connectorHeight: CGFloat { 34 }

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

    /// The rail leaving a completed node is earned road; everything past the
    /// frontier is dimmed so the eye stops where you actually stopped.
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

            Image(systemName: nodeIcon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(nodeTint)
        }
        .frame(width: Self.nodeSize, height: Self.nodeSize)
        // The current node is the only lit object on the screen — it answers
        // "where do I tap" without a label saying so.
        .shadow(
            color: state == .current ? AppColors.primary.opacity(0.45) : .clear,
            radius: state == .current ? 14 : 0,
            y: 4
        )
        .opacity(state == .locked ? 0.5 : 1)
    }

    private var nodeIcon: String {
        switch state {
        case .completed: return "checkmark"
        case .current: return "play.fill"
        case .available: return icon
        case .locked: return "lock.fill"
        }
    }

    private var nodeFill: Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.18)
        case .current: return AppColors.primary.opacity(0.22)
        case .available, .locked: return .white.opacity(0.05)
        }
    }

    private var nodeStroke: Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.5)
        case .current: return AppColors.primary
        case .available, .locked: return AppColors.cardStroke
        }
    }

    private var nodeTint: Color {
        switch state {
        case .completed: return AppColors.success
        case .current: return AppColors.primary
        case .available: return .white.opacity(0.7)
        case .locked: return .white.opacity(0.4)
        }
    }
}

/// The connecting rail between two nodes. A cubic with vertical control points
/// so it leaves and enters each node straight down, rather than cutting a
/// diagonal across the gap.
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
                icon: "book",
                isLeading: true,
                hasNext: true,
                nextIsLeading: false
            ) {
                Text("Finding your baseline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            LessonPathRow(
                state: .current,
                icon: "book",
                isLeading: false,
                hasNext: true,
                nextIsLeading: true
            ) {
                Text("Cutting filler words")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            LessonPathRow(
                state: .locked,
                icon: "book",
                isLeading: true,
                hasNext: false,
                nextIsLeading: false
            ) {
                Text("Pacing under pressure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .background(AppBackground())
}
