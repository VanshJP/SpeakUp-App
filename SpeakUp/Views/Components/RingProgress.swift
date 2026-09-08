import SwiftUI

struct RingProgress: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    /// Some rings are indeterminate spinners rather than measurements — those
    /// pass a fixed trim and rotate the whole view instead.
    var trimStart: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.meterTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: trimStart, to: max(trimStart, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        RingProgress(progress: 0.75, color: AppColors.scoreHigh, lineWidth: 8)
            .frame(width: 78, height: 78)
        RingProgress(progress: 0.35, color: AppColors.warning, lineWidth: 4)
            .frame(width: 44, height: 44)
        RingProgress(progress: 0.9, color: AppColors.primary, lineWidth: 11)
            .frame(width: 110, height: 110)
    }
    .padding(40)
    .background(AppBackground())
}
