import SwiftUI
import UIKit

/// Renders the Then-vs-Now progress card and hands it to the share sheet.
///
/// Private by default: it takes a `ProgressCardData`, which has no transcript,
/// prompt, story title, or audio on it at all. Sharing progress should never
/// require sharing what you said.
@MainActor
enum ProgressCardRenderer {
    static func render(_ data: ProgressCardData) -> UIImage? {
        let renderer = ImageRenderer(content: ProgressCardView(data: data))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    /// Renders and presents the system share sheet.
    @discardableResult
    static func share(
        _ data: ProgressCardData,
        trigger: String,
        onShared: (() -> Void)? = nil
    ) -> Bool {
        guard let image = render(data) else { return false }
        return SharePresenter.present(
            image: image,
            cardType: "then_vs_now",
            trigger: trigger,
            onShared: onShared
        )
    }
}

// MARK: - Card

private struct ProgressCardView: View {
    let data: ProgressCardData

    var body: some View {
        ZStack {
            AppBackground(style: .primary)

            VStack(spacing: 26) {
                brandRow
                headline
                scorePair
                rowsGrid
                footnote
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 40)
        }
        .frame(width: 400)
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("BigTalkOrb")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("Big Talk")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("Then vs Now")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var headline: some View {
        VStack(spacing: 4) {
            Text(data.headline)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(data.delta > 0 ? AppColors.success : .white)
            Text(data.subheadline)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var scorePair: some View {
        HStack(spacing: 0) {
            scoreColumn(label: "First", score: data.firstScore, muted: true)

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 44)

            scoreColumn(label: "Latest", score: data.latestScore, muted: false)
        }
    }

    private func scoreColumn(label: String, score: Int, muted: Bool) -> some View {
        VStack(spacing: 6) {
            Text("\(score)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(muted ? Color.white.opacity(0.45) : AppColors.scoreColor(for: score))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var rowsGrid: some View {
        VStack(spacing: 10) {
            ForEach(data.rows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text("\(row.before)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 6)

                    Text("\(row.after)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(rowColor(row))
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
        }
    }

    private func rowColor(_ row: ProgressCardData.Row) -> Color {
        guard row.changed else { return .white.opacity(0.6) }
        return row.improved ? AppColors.success : .white.opacity(0.6)
    }

    private var footnote: some View {
        Text("Practised on device with Big Talk")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.3))
    }
}
