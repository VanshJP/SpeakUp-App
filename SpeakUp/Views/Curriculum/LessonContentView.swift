import SwiftUI

struct LessonContentView: View {
    let content: LessonContent

    var body: some View {
        VStack(spacing: 16) {
            ForEach(content.sections) { section in
                sectionView(for: section)
            }
        }
    }

    // MARK: - Section Dispatch

    @ViewBuilder
    private func sectionView(for section: LessonSection) -> some View {
        switch section.type {
        case .concepts:
            conceptsSection(section)
        case .tip:
            tipSection(section)
        case .example:
            exampleSection(section)
        case .keyTakeaway:
            keyTakeawaySection(section)
        case .callout:
            calloutSection(section)
        }
    }

    // MARK: - Concepts

    private func conceptsSection(_ section: LessonSection) -> some View {
        GlassCard(tint: Color.blue.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 14) {
                if let title = section.title {
                    Label {
                        Text(title)
                            .font(.headline)
                    } icon: {
                        Image(systemName: section.icon ?? "book")
                            .foregroundStyle(.blue)
                    }
                }

                let bullets = section.body.components(separatedBy: "\n").filter { !$0.isEmpty }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(.blue.opacity(0.6))
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)

                            Text(bullet)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tip

    private func tipSection(_ section: LessonSection) -> some View {
        GlassCard(tint: Color.orange.opacity(0.08)) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.orange)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text(section.title ?? "Pro Tip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } icon: {
                        Image(systemName: section.icon ?? "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(section.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Example

    private func exampleSection(_ section: LessonSection) -> some View {
        GlassCard(tint: Color.indigo.opacity(0.08)) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.indigo)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text(section.title ?? "Example")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                    } icon: {
                        Image(systemName: section.icon ?? "quote.opening")
                            .foregroundStyle(.indigo)
                    }

                    Text(section.body)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Key Takeaway

    private func keyTakeawaySection(_ section: LessonSection) -> some View {
        FeaturedGlassCard(gradientColors: [AppColors.primary.opacity(0.15), .cyan.opacity(0.08)]) {
            HStack(spacing: 14) {
                Image(systemName: section.icon ?? "star.fill")
                    .font(.title)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.primary.opacity(0.15)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title ?? "Key Takeaway")
                        .font(.subheadline.weight(.semibold))

                    Text(section.body)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Callout

    private func calloutSection(_ section: LessonSection) -> some View {
        GlassCard(tint: AppColors.glassTintSuccess) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.green)
                    .frame(width: 3)

                HStack(spacing: 12) {
                    Image(systemName: section.icon ?? "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 8) {
                        if let title = section.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(section.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
